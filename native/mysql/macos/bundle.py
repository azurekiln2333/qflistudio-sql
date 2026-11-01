#!/usr/bin/env python3
"""Build, relocate and sign Oracle helpers during the macOS Runner build."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import posixpath
import re
import shutil
import struct
import subprocess
import sys
import tempfile


ORACLE_VERSION = "8.4.6"
ARCHITECTURES = {"arm64": (0x0100000C, "arm64"), "x86_64": (0x01000007, "x64")}
DYLIB_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x80000023}
MACHO_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def version(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid macOS version: {value}")
    return tuple((list(map(int, value.split("."))) + [0, 0])[:3])


def unpack_version(value: int) -> tuple[int, int, int]:
    return value >> 16, (value >> 8) & 255, value & 255


def read_macho(path: Path) -> dict:
    # Read only the bounded Mach-O header/load commands, never server data.
    with path.open("rb") as stream:
        header = stream.read(32)
        if len(header) != 32 or header[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError(f"Expected a thin 64-bit Mach-O: {path}")
        _, cpu, _, kind, count, size, _, _ = struct.unpack("<8I", header)
        if size > 16 * 1024 * 1024 or count > size // 8:
            raise ValueError(f"Invalid Mach-O command table: {path}")
        commands = stream.read(size)
    if len(commands) != size:
        raise ValueError(f"Truncated Mach-O command table: {path}")
    dependencies, rpaths, platforms, minimums = [], [], [], []
    offset = 0
    for _ in range(count):
        if offset + 8 > size:
            raise ValueError(f"Truncated Mach-O load command: {path}")
        command, length = struct.unpack_from("<2I", commands, offset)
        if length < 8 or length % 8 or offset + length > size:
            raise ValueError(f"Invalid Mach-O load command size: {path}")
        data = commands[offset:offset + length]
        if command in DYLIB_COMMANDS or command in {0xD, 0x8000001C}:
            minimum = 12 if command == 0x8000001C else 24
            if length < minimum:
                raise ValueError(f"Invalid Mach-O string command: {path}")
            start = struct.unpack_from("<I", data, 8)[0]
            if start < minimum or start >= length or b"\0" not in data[start:]:
                raise ValueError(f"Invalid Mach-O string offset: {path}")
            value = data[start:].split(b"\0", 1)[0].decode("utf-8")
            if command in DYLIB_COMMANDS:
                dependencies.append(value)
            elif command == 0x8000001C:
                rpaths.append(value)
        elif command == 0x32:
            if length < 24:
                raise ValueError(f"Invalid LC_BUILD_VERSION: {path}")
            target, minimum, _, tools = struct.unpack_from("<4I", data, 8)
            if length < 24 + tools * 8:
                raise ValueError(f"Invalid LC_BUILD_VERSION tools: {path}")
            platforms.append(target)
            minimums.append(unpack_version(minimum))
        elif command in {0x24, 0x25, 0x2F, 0x30}:
            if length < 16:
                raise ValueError(f"Invalid minimum OS command: {path}")
            platforms.append(1 if command == 0x24 else -1)
            minimums.append(unpack_version(struct.unpack_from("<I", data, 8)[0]))
        offset += length
    if offset != size:
        raise ValueError(f"Trailing Mach-O load commands: {path}")
    return {"cpu": cpu, "kind": kind, "dependencies": dependencies,
            "rpaths": rpaths, "platforms": platforms, "minimums": minimums}


def validate_target(path: Path, architecture: str, deployment: str) -> dict:
    info = read_macho(path)
    if info["cpu"] != ARCHITECTURES[architecture][0]:
        raise ValueError(f"Wrong architecture for {architecture}: {path}")
    if not info["platforms"] or any(item != 1 for item in info["platforms"]):
        raise ValueError(f"Not a macOS native input: {path}")
    if any(item > version(deployment) for item in info["minimums"]):
        raise ValueError(f"Native input requires a newer OS than macOS {deployment}: {path}")
    if info["kind"] not in {2, 6, 8}:
        raise ValueError(f"Unsupported Mach-O file type: {path}")
    return info


def is_system(dependency: str) -> bool:
    return posixpath.normpath(dependency).startswith(("/usr/lib/", "/System/Library/"))


def native_files(root: Path) -> list[Path]:
    result = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO_MAGICS:
                    result.append(path)
    return result


def dependency_path(dependency: str, loader: Path, contents: Path, rpaths: list[str]) -> Path:
    def expand(value: str) -> Path:
        if value.startswith("@loader_path/"):
            return loader.parent / value[len("@loader_path/"):]
        if value.startswith("@executable_path/"):
            return contents / "MacOS" / value[len("@executable_path/"):]
        return Path(value)

    if dependency.startswith("@rpath/"):
        tail = dependency[len("@rpath/"):]
        candidates = [expand(item) / tail for item in rpaths]
        candidates.append(contents / "Frameworks" / tail)
    else:
        candidates = [expand(dependency)]
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_relative_to(contents.resolve()) and resolved.is_file():
            return resolved
    raise ValueError(f"Unresolved or external dependency {dependency} in {loader}")


def validate_closure(contents: Path, architecture: str, deployment: str) -> list[Path]:
    files = native_files(contents)
    resolved_files = {path.resolve() for path in files}
    for path in files:
        if not path.resolve().is_relative_to(contents.resolve()):
            raise ValueError(f"External native symlink: {path}")
        info = validate_target(path, architecture, deployment)
        if info["rpaths"]:
            raise ValueError(f"Unrelocated native RPATH: {path}")
        for dependency in info["dependencies"]:
            if not is_system(dependency):
                if not dependency.startswith("@loader_path/"):
                    raise ValueError(f"Non-loader-relative dependency: {dependency} in {path}")
                target = dependency_path(dependency, path, contents, [])
                if target not in resolved_files:
                    raise ValueError(f"Dependency is not packaged native code: {target}")
    return files


def copy_native(source: Path, destination: Path, architecture: str, deployment: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise ValueError(f"Duplicate native destination: {destination}")
    architectures = run("lipo", "-archs", str(source)).split()
    if architecture not in architectures:
        raise ValueError(f"Missing {architecture} input: {source}")
    if len(architectures) == 1:
        shutil.copy2(source.resolve(), destination)
    else:
        run("lipo", str(source), "-thin", architecture, "-output", str(destination))
    destination.chmod(0o755)
    validate_target(destination, architecture, deployment)


def build_helper(root: Path, sdk: Path, temporary: Path, architecture: str,
                 deployment: str, identity: str, identifier: str) -> tuple[Path, dict]:
    header = sdk / "include/mysql_version.h"
    text = header.read_text(encoding="utf-8")
    if not re.search(r'^\s*#\s*define\s+MYSQL_SERVER_VERSION\s+"8\.4\.6"', text, re.MULTILINE):
        raise ValueError(f"The full Oracle {ORACLE_VERSION} SDK is required: {sdk}")
    for required in (sdk / "bin/mysqld", sdk / "share", sdk / "lib", sdk / "LICENSE"):
        if not required.exists():
            raise ValueError(f"Incomplete Oracle SDK: {required}")
    build = temporary / f"build-{architecture}"
    run("cmake", "-S", str(root / "native/mysql/desktop"), "-B", str(build),
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_OSX_ARCHITECTURES={architecture}",
        f"-DCMAKE_OSX_DEPLOYMENT_TARGET={deployment}", f"-DQFLI_ORACLE_HOME={sdk}",
        f"-DQFLI_MYSQL_SOURCE={os.environ.get('QFLI_MYSQL_SOURCE', root / 'build/mysql-port/mysql-8.4.6')}")
    run("cmake", "--build", str(build), "--config", "Release", "--parallel", "2")
    abi = ARCHITECTURES[architecture][1]
    helper = temporary / f"QfliMySql-{abi}.app"
    contents = helper / "Contents"
    for directory in ("MacOS", "Frameworks", "PlugIns", "Resources"):
        (contents / directory).mkdir(parents=True)
    inputs = {"include/mysql_version.h": digest(header)}

    def copy(source: Path, target: Path) -> None:
        copy_native(source, target, architecture, deployment)
        label = str(source.relative_to(sdk)) if source.is_relative_to(sdk) else f"built/{source.name}"
        inputs[label] = digest(source)

    copy(sdk / "bin/mysqld", contents / "MacOS/mysqld")
    copy(build / "qfli_mysql_launcher", contents / "MacOS/qfli_mysql_launcher")
    copy(build / "libqfli_mysql_bridge.dylib", contents / "Frameworks/libqfli_mysql_bridge.dylib")
    # Oracle keeps plugins under lib/plugin and its other dylibs under lib/private.
    plugins = sdk / "lib/plugin"
    sdk_native_files = native_files(sdk / "lib")
    for source in sdk_native_files:
        if source.is_relative_to(plugins):
            target = contents / "PlugIns" / source.relative_to(plugins)
        else:
            target = contents / "Frameworks" / source.name
        copy(source, target)
    if plugins.is_dir():
        native_sources = set(sdk_native_files)
        for source in plugins.rglob("*"):
            if source.is_file() and source not in native_sources:
                if source.suffix in {".so", ".dylib"}:
                    raise ValueError(f"Plugin is not a macOS native library: {source}")
                if source.suffix not in {".a", ".la"}:
                    target = contents / "PlugIns" / source.relative_to(plugins)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
    for directory in ("share", "docs", "licenses"):
        if (sdk / directory).is_dir():
            shutil.copytree(sdk / directory, contents / "Resources" / directory)
    for filename in ("LICENSE", "README", "runtime.json"):
        if (sdk / filename).is_file():
            shutil.copy2(sdk / filename, contents / "Resources" / filename)
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": f"{identifier}.mysql.{abi}",
        "CFBundleName": f"QfliMySql-{abi}", "CFBundlePackageType": "APPL",
        "CFBundleExecutable": "qfli_mysql_launcher", "CFBundleVersion": ORACLE_VERSION,
        "CFBundleShortVersionString": ORACLE_VERSION, "LSMinimumSystemVersion": deployment,
        "LSUIElement": True,
    }))
    run("cmake", f"-DHELPER_APP={helper}", f"-DORACLE_HOME={sdk}",
        "-P", str(root / "native/mysql/macos/fixup.cmake"))
    # BundleUtilities can materialize a universal dependency from the SDK.
    for path in native_files(contents):
        if len(run("lipo", "-archs", str(path)).split()) > 1:
            thin = path.with_name(path.name + ".thin")
            run("lipo", str(path), "-thin", architecture, "-output", str(thin))
            thin.chmod(0o755)
            thin.replace(path)
    for path in native_files(contents):
        info = validate_target(path, architecture, deployment)
        for dependency in info["dependencies"]:
            if is_system(dependency):
                continue
            target = dependency_path(dependency, path, contents, info["rpaths"])
            replacement = "@loader_path/" + os.path.relpath(target, path.parent)
            run("install_name_tool", "-change", dependency, replacement, str(path))
        if info["kind"] == 6:
            run("install_name_tool", "-id", f"@loader_path/{path.name}", str(path))
        for rpath in dict.fromkeys(info["rpaths"]):
            run("install_name_tool", "-delete_rpath", rpath, str(path))
    files = validate_closure(contents, architecture, deployment)
    sign = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        sign += ["--options", "runtime", "--timestamp"]
    entitlements = str(root / "native/mysql/macos/Helper.entitlements")
    for path in sorted(files, key=lambda item: read_macho(item)["kind"] == 2):
        options = ["--entitlements", entitlements] if read_macho(path)["kind"] == 2 else []
        run(*sign, *options, str(path))
    run(*sign, "--entitlements", entitlements, str(helper))
    run("codesign", "--verify", "--deep", "--strict", str(helper))
    manifest = {"architecture": architecture, "oracleVersion": ORACLE_VERSION,
                "minimumMacOS": deployment, "nativeInputs": inputs,
                "files": {str(path.relative_to(helper)): digest(path)
                          for path in sorted(helper.rglob("*")) if path.is_file()}}
    return helper, manifest


def main() -> None:
    if sys.platform != "darwin":
        raise ValueError("Oracle macOS packaging requires a macOS host with Xcode.")
    root = Path(__file__).resolve().parents[3]
    target = Path(os.environ["TARGET_BUILD_DIR"]).resolve()
    contents = (target / os.environ["CONTENTS_FOLDER_PATH"]).resolve()
    if not contents.is_relative_to(target) or contents == target:
        raise ValueError("The app Contents directory must be inside TARGET_BUILD_DIR.")
    deployment = os.environ["MACOSX_DEPLOYMENT_TARGET"]
    version(deployment)
    architectures = list(dict.fromkeys(os.environ["ARCHS"].split()))
    if not architectures or any(item not in ARCHITECTURES for item in architectures):
        raise ValueError(f"Unsupported Xcode architectures: {architectures}")
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY") or "-"
    identifier = os.environ["PRODUCT_BUNDLE_IDENTIFIER"]
    derived = Path(os.environ["DERIVED_FILE_DIR"]).resolve()
    derived.mkdir(parents=True, exist_ok=True)
    helpers = contents / "Helpers"
    helpers.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="qfli-mysql-", dir=derived) as work:
        manifests = []
        staged = []
        for architecture in architectures:
            key = f"QFLI_MYSQL_MACOS_{ARCHITECTURES[architecture][1].upper()}"
            if not os.environ.get(key):
                raise ValueError(f"Set {key} to the complete Oracle {ORACLE_VERSION} macOS SDK.")
            sdk = Path(os.environ[key]).resolve(strict=True)
            helper, manifest = build_helper(root, sdk, Path(work), architecture,
                                            deployment, identity, identifier)
            staged.append(helper)
            manifests.append(manifest)
        for abi in ("arm64", "x64"):
            destination = helpers / f"QfliMySql-{abi}.app"
            if destination.is_symlink() or destination.parent.resolve() != (contents / "Helpers").resolve():
                raise ValueError(f"Invalid helper destination: {destination}")
            if destination.exists():
                shutil.rmtree(destination)
        for helper in staged:
            shutil.move(str(helper), helpers / helper.name)
        resources = contents / "Resources"
        resources.mkdir(parents=True, exist_ok=True)
        (resources / "qfli-mysql-runtime.json").write_text(
            json.dumps({"format": 1, "helpers": manifests}, indent=2) + "\n", encoding="utf-8")
    print("Oracle macOS helper packaging and signing completed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Oracle macOS packaging failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.output, file=sys.stderr)
        sys.exit(1)
