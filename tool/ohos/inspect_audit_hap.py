"""Verify the original-catalog x86_64 audit HAP without touching a device.

Uses the installed SDK's own strip, ELF and signature tools. A PASS proves
package identity and static consistency only, never runtime acceptance.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import tempfile
import zipfile


MYSQL_LIBRARIES = (
    "libqfli_mysql.so", "libqfli_mysql_server.so",
    "libqfli_mysql_launcher.so", "libqfli_mysql_server_proto.so",
)
PRIVATE_EXPORTS = {
    "QfliMysqlMain", "qfli_mysql_child_main", "qfli_mysql_record_exit",
    "qfli_mysql_proto_report", "qfli_mysql_proto_ready",
    "qfli_mysql_proto_enter_child_scope", "qfli_mysql_proto_child_exit",
}
AUDIT_TARGET = "integration_test/sql_curriculum_ohos_audit.dart"
FLUTTER_ASSETS = "resources/rawfile/flutter_assets/"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_permissions(request_permissions: list[dict]) -> list[str]:
    permissions = sorted(item["name"] for item in request_permissions)
    require(permissions == ["ohos.permission.INTERNET",
                            "ohos.permission.READ_PASTEBOARD"],
            "Audit HAP requires exactly ohos.permission.INTERNET and "
            "ohos.permission.READ_PASTEBOARD; extra, duplicate or missing "
            "permissions are forbidden. This check does not verify that INTERNET "
            "is used only for the requested same-device loopback path")
    return permissions


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def run(*arguments: str | Path) -> str:
    result = subprocess.run(
        [str(argument) for argument in arguments], capture_output=True,
        text=True, encoding="utf-8", errors="replace", timeout=60,
    )
    require(result.returncode == 0,
            f"Command failed: {arguments[0]} {arguments[1:]}\n"
            f"{result.stdout}\n{result.stderr}")
    return result.stdout


def check_names(names: list[str]) -> None:
    duplicates = [name for name, count in Counter(names).items() if count != 1]
    require(not duplicates, f"Duplicate archive entries: {duplicates}")
    require(all(not PurePosixPath(name).is_absolute()
                and ".." not in PurePosixPath(name).parts
                and "\\" not in name for name in names), "Unsafe archive path")


def elf_machine(data: bytes) -> int:
    require(len(data) >= 64 and data[:6] == b"\x7fELF\x02\x01",
            "Expected a little-endian ELF64 image")
    return struct.unpack_from("<H", data, 18)[0]


def check_catalog(examples: dict, tutorials: dict, count: int, scripts: int) -> dict:
    entries = examples["entries"]
    tutorial_entries = tutorials["entries"]
    require(len(entries) == len(tutorial_entries) == count,
            "Catalog example/tutorial count differs from the required original catalog")
    require(len({entry["id"] for entry in entries}) == count, "Duplicate example ID")
    require(len({entry["id"] for entry in tutorial_entries}) == count,
            "Duplicate tutorial ID")
    require({entry["id"] for entry in entries}
            == {f"sql-example-{number:03d}" for number in range(1, count + 1)},
            "Missing/unexpected original example IDs")
    require({entry["id"] for entry in tutorial_entries}
            == {f"sql-tutorial-{number:03d}" for number in range(1, count + 1)},
            "Missing/unexpected original tutorial IDs")
    lessons = [lesson for tutorial in tutorial_entries for lesson in tutorial["lessons"]]
    require(len(lessons) == count, "Expected one paired lesson per original example")
    by_id = {lesson["id"]: lesson for lesson in lessons}
    require(len(by_id) == count, "Duplicate lesson ID")
    require({entry["sourceLessonId"] for entry in entries} == set(by_id),
            "Every lesson requires exactly one paired example")
    engines: Counter[str] = Counter()
    exercise_count = 0
    for entry in entries:
        lesson = by_id.get(entry["sourceLessonId"])
        require(lesson is not None, f"Missing lesson for {entry['id']}")
        require(entry["code"] == lesson["code"]
                and entry["output"] == lesson["output"]
                and entry["expectedOutput"] == entry["output"],
                f"Example/lesson code/output mismatch: {entry['id']}")
        fixtures = entry["inputFixtures"]
        engine = fixtures["engine"]
        require(engine in {"sqlite", "mysql"}, f"Unknown engine: {engine}")
        outputs = json.loads(fixtures["exerciseExpectedOutputs"])
        exercises = lesson["exercises"]
        require(len(outputs) == len(exercises) and len(exercises) > 0,
                f"Incomplete original exercise coverage: {entry['id']}")
        require(all(isinstance(output, str) and output.strip() for output in outputs),
                "Invalid expected output")
        require(all(exercise["answer"].strip() for exercise in exercises), "Empty exercise answer")
        exercise_count += len(exercises)
        engines[engine] += 1 + len(exercises)
    require(count + exercise_count == scripts, "Unexpected total script denominator")
    return {"examples": count, "lessons": len(lessons), "exercises": exercise_count,
            "scripts": scripts, "scriptsByEngine": dict(engines)}


def check_symbol_closure(llvm: Path, packaged: Path, platform: Path,
                         names: set[str]) -> dict:
    """Resolve strong symbol names against each image's actual NEEDED graph.

    SDK stubs prove the link interface, not the selected device's loader/runtime.
    Weak undefined symbols are optional and do not cause a false missing import.
    """
    cache: dict[str, tuple[set[str], set[str], list[str]]] = {}

    def symbols(name: str) -> tuple[set[str], set[str], list[str]]:
        if name not in cache:
            image = packaged / name
            if not image.is_file():
                image = platform / name
            output = run(llvm / "llvm-nm.exe", "-D", "--format=posix", image)
            defined: set[str] = set()
            undefined: set[str] = set()
            for line in output.splitlines():
                fields = line.split()
                if len(fields) < 2:
                    continue
                symbol, kind = fields[0].split("@")[0], fields[1]
                if kind == "U":
                    undefined.add(symbol)
                elif kind not in {"w", "v"}:
                    defined.add(symbol)
            dynamic = run(llvm / "llvm-readelf.exe", "-d", image)
            dependencies = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
            cache[name] = defined, undefined, dependencies
        return cache[name]

    def closure(name: str, seen: set[str]) -> set[str]:
        if name in seen:
            return set()
        seen.add(name)
        defined, _, dependencies = symbols(name)
        result = set(defined)
        for dependency in dependencies:
            result.update(closure(dependency, seen))
        return result

    results = {}
    for name in sorted(names):
        _, undefined, _ = symbols(name)
        unresolved = undefined - closure(name, set())
        require(not unresolved, f"Unresolved strong SDK imports: {name}: {sorted(unresolved)}")
        results[name] = {"strongImports": len(undefined), "unresolved": sorted(unresolved)}
    return results


def inspect(args: argparse.Namespace, report: dict) -> None:
    root = Path(__file__).resolve().parents[2]
    output = root / "build/ohos-audit"
    artifact = output / "sql-audit-signed.hap"
    unsigned = output / "sql-audit-unsigned.hap"
    metadata = read_json(output / "build.json")
    staging = read_json(root / "build/mysql-port/package/libs/x86_64/staging.json")
    report["artifact"] = {"path": str(artifact), "bytes": artifact.stat().st_size,
                          "sha256": file_digest(artifact)}
    require(metadata["signed"] is True, "Build record is not signed")
    require(report["artifact"]["sha256"] == metadata["signedSha256"].lower(),
            "Signed HAP hash differs from build record")
    require(file_digest(unsigned) == metadata["unsignedSha256"].lower(),
            "Unsigned HAP hash differs from build record")
    require(metadata["architecture"] == "ohos-x64", "Inspector requires an x86_64 audit build")
    require(metadata["target"] == AUDIT_TARGET, "Build record selects a different entrypoint")
    defines = dict(item.split("=", 1) for item in metadata["dartDefines"])
    require(set(defines.get("QFLI_SQL_CURRICULUM_ENGINES", "sqlite,mysql").split(","))
            == {"sqlite", "mysql"}, "Audit build must select both original engines")
    sdk = Path(args.sdk)
    llvm = sdk / "native/llvm/bin"
    report["tools"] = {name: {"path": str(llvm / name), "sha256": file_digest(llvm / name)}
                       for name in ("llvm-strip.exe", "llvm-readelf.exe", "llvm-nm.exe")}
    report["tools"]["llvmVersion"] = run(llvm / "llvm-readelf.exe", "--version").strip()
    with tempfile.TemporaryDirectory(prefix="qfli-hap-inspect-") as temporary:
        temp = Path(temporary)
        with zipfile.ZipFile(artifact) as archive, zipfile.ZipFile(unsigned) as original:
            names = archive.namelist()
            check_names(names)
            check_names(original.namelist())
            require(set(names) == set(original.namelist()) | {".pages.info"},
                    "Signing changed ZIP entries beyond SDK code-sign metadata")
            report["zipEntries"] = len(names)
            # Streaming comparisons avoid retaining the large native images twice.
            for name in original.namelist():
                with archive.open(name) as signed_stream, original.open(name) as unsigned_stream:
                    require(hashlib.file_digest(signed_stream, "sha256").digest()
                            == hashlib.file_digest(unsigned_stream, "sha256").digest(),
                            f"Signing changed ZIP payload: {name}")
            manifest = json.loads(archive.read("module.json"))
            app = manifest["app"]
            module = manifest["module"]
            require(app["bundleName"] == metadata["bundleName"]
                    and re.fullmatch(r"com\.azurekiln\.qfli\.sqlab\.[a-z][a-z0-9.]*",
                                     app["bundleName"]) is not None, "Wrong audit bundle")
            require(app["debug"] is True and app["buildMode"] == "debug", "Expected debug HAP")
            require(module["type"] == "entry" and module["mainElement"] == "EntryAbility",
                    "Unexpected native entrypoint")
            permissions = check_permissions(module.get("requestPermissions", []))
            require(json.loads(archive.read("pack.info"))["summary"]["app"]["bundleName"]
                    == app["bundleName"], "Pack-info bundle mismatch")
            report["manifest"] = {"bundle": app["bundleName"], "debug": app["debug"],
                                  "compileSdkVersion": app["compileSdkVersion"],
                                  "permissions": permissions, "target": metadata["target"]}
            catalog = {}
            report["catalogAssets"] = {}
            for kind in ("examples", "tutorials"):
                relative = f"assets/content/sql_{kind}.json"
                packaged = archive.read(FLUTTER_ASSETS + relative)
                require(packaged == (root / relative).read_bytes(), f"Stale catalog asset: {relative}")
                report["catalogAssets"][relative] = digest(packaged)
                catalog[kind] = json.loads(packaged)
            report["catalog"] = check_catalog(catalog["examples"], catalog["tutorials"],
                                              args.expected_examples, args.expected_scripts)
            kernel = archive.read(FLUTTER_ASSETS + "kernel_blob.bin")
            require(AUDIT_TARGET.encode() in kernel
                    and (root / AUDIT_TARGET).read_bytes().replace(b"\r\n", b"\n")
                    in kernel.replace(b"\r\n", b"\n"), "Kernel lacks the current audit source")
            build_id = defines.get("QFLI_SQL_CURRICULUM_BUILD_ID", "")
            require(bool(build_id) and build_id.encode() in kernel, "Kernel lacks recorded build ID")
            report["kernel"] = {"sha256": digest(kernel), "bytes": len(kernel),
                                "buildId": build_id, "currentAuditSourceEmbedded": True,
                                "entryExecutionVerified": False}
            resource_root = root / "build/mysql-port/package/rawfile/mysql"
            runtime = json.loads(archive.read("resources/rawfile/mysql/runtime.json"))
            require(runtime["version"] == "8.4.6" and len(runtime["files"]) == 70,
                    "Oracle original runtime/resource inventory changed")
            resource_names = {"runtime.json", *runtime["files"]}
            require(len(resource_names) == 71, "Duplicate Oracle resource path")
            resource_files = {file.relative_to(resource_root).as_posix()
                              for file in resource_root.rglob("*") if file.is_file()}
            require(resource_names <= resource_files, "Missing local Oracle runtime resource")
            require({name.removeprefix("resources/rawfile/mysql/") for name in names
                     if name.startswith("resources/rawfile/mysql/")} == resource_files,
                    "Packaged Oracle resources differ from staged resource files")
            for name in resource_files:
                require(archive.read("resources/rawfile/mysql/" + name)
                        == (resource_root / name).read_bytes(), f"Stale Oracle resource: {name}")
            report["oracleResources"] = {"version": runtime["version"], "files": 70,
                                         "otherFiles": sorted(resource_files - resource_names),
                                         "manifestSha256": digest(archive.read("resources/rawfile/mysql/runtime.json"))}
            libraries = {}
            for name in names:
                if not name.startswith("libs/") or not name.endswith(".so"):
                    continue
                _, abi, filename = name.split("/")
                data = archive.read(name)
                require(abi in {"x86_64", "arm64-v8a"}, f"Unexpected ABI: {abi}")
                require(elf_machine(data) == {"x86_64": 62, "arm64-v8a": 183}[abi],
                        f"ELF/path architecture mismatch: {name}")
                libraries[name] = {"bytes": len(data), "sha256": digest(data), "abi": abi}
                if abi == "x86_64":
                    (temp / filename).write_bytes(data)
            required = {*MYSQL_LIBRARIES, "libqfli_sql.so", "libflutter.so", "libc++_shared.so"}
            require(all(f"libs/x86_64/{name}" in libraries for name in required),
                    "Missing x86_64 runtime library")
            for filename in MYSQL_LIBRARIES:
                candidate = root / "build/mysql-port/package/libs/x86_64" / filename
                identity = staging["artifacts"][filename]
                require(file_digest(candidate) == identity["packagedSha256"].lower()
                        and candidate.stat().st_size == identity["packagedBytes"],
                        f"Staging identity drift: {filename}")
                transformed = temp / (filename + ".stripped")
                run(llvm / "llvm-strip.exe", "--strip-all", candidate, "-o", transformed)
                library = libraries["libs/x86_64/" + filename]
                require(file_digest(transformed) == library["sha256"],
                        f"HAP image is not the SDK strip transform of audited Oracle: {filename}")
                library["auditedCandidateSha256"] = identity["packagedSha256"].lower()
                library["transform"] = "SDK llvm-strip --strip-all"
            sdk_libs = sdk / "native/sysroot/usr/lib/x86_64-linux-ohos"
            for filename in required:
                dynamic = run(llvm / "llvm-readelf.exe", "-d", temp / filename)
                dependencies = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
                require("(TEXTREL)" not in dynamic, f"Text relocations: {filename}")
                require(all(dependency in required or (sdk_libs / dependency).is_file()
                            for dependency in dependencies), f"Unresolved NEEDED library: {filename}")
                libraries["libs/x86_64/" + filename]["needed"] = dependencies
            private = temp / "libqfli_mysql_server_proto.so"
            require(libraries["libs/x86_64/" + private.name]["needed"] == ["libc.so"],
                    "Private Oracle server imports non-libc dependencies")
            symbols = run(llvm / "llvm-nm.exe", "-D", "--defined-only", "--format=posix", private)
            exports = {line.split()[0].split("@")[0] for line in symbols.splitlines()}
            require(exports == PRIVATE_EXPORTS, "Private Oracle export boundary changed")
            imports = run(llvm / "llvm-nm.exe", "-D", "--undefined-only", private)
            require(not re.search(r"__call_once|__cxa_guard|__gxx_personality|_Unwind_|"
                                  r"__cxa_throw|__cxa_allocate_exception|_ZSt|_ZNSt", imports),
                    "Private Oracle imports external C++/unwind state")
            report["libraries"] = libraries
            report["privateOracleExports"] = sorted(exports)
            report["sdkSymbolClosure"] = check_symbol_closure(
                llvm, temp, sdk_libs, required - {"libflutter.so"})
            report["platformDependencyScope"] = (
                "NEEDED names present in installed x86_64 SDK; strong import names resolved "
                "for Oracle/SQLite/libc++; no device load or symbol-version runtime claim")
        java = Path(args.jdk) / "bin/java.exe"
        jar = sdk / "toolchains/lib/hap-sign-tool.jar"
        report["tools"]["hap-sign-tool.jar"] = {"path": str(jar), "sha256": file_digest(jar)}
        signature_log = run(java, "-jar", jar, "verify-app", "-inFile", artifact,
                            "-outCertChain", temp / "chain.cer", "-outProfile", temp / "profile.p7b")
        require("verify-app success" in signature_log, "Signature tool did not confirm verification")
        profile_log = run(java, "-jar", jar, "verify-profile", "-inFile", temp / "profile.p7b",
                          "-outFile", temp / "profile.json")
        report["signature"] = {"verified": True, "tool": str(jar),
                               "profileResult": read_json(temp / "profile.json"),
                               "verifyLog": signature_log, "profileLog": profile_log}
        profile_result = report["signature"]["profileResult"]
        require(profile_result.get("verifiedPassed") is True, "Profile signature verification failed")
        profile = profile_result.get("content")
        require(isinstance(profile, dict), "SDK verification did not return profile content")
        require(profile["bundle-info"]["bundle-name"] == metadata["bundleName"]
                and profile["type"] == "debug" and profile["bundle-info"]["apl"] == "normal",
                "Signed profile identity/type/privilege mismatch")
        require(profile["debug-info"]["device-id-type"] == "udid"
                and len(profile["debug-info"]["device-ids"]) == 1, "Unexpected profile device scope")
        require(profile == read_json(output / "audit-profile.json"),
                "Signed profile differs from the audit signing input")
        now = datetime.now(timezone.utc).timestamp()
        require(profile["validity"]["not-before"] <= now < profile["validity"]["not-after"],
                "Audit profile is not currently valid")
    report["status"] = "PASS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", default="D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony")
    parser.add_argument("--jdk", default="D:/ProgramFiles/Huawei/DevEco Studio/jbr")
    parser.add_argument("--expected-examples", type=int, default=126)
    parser.add_argument("--expected-scripts", type=int, default=372)
    parser.add_argument("--report", type=Path,
                        default=Path(__file__).resolve().parents[2] / "build/ohos-audit/inspection.json")
    args = parser.parse_args()
    report = {"status": "FAIL", "checkedAt": datetime.now(timezone.utc).isoformat(),
              "scope": "static x86_64 original-catalog audit package", "deviceExecuted": False}
    try:
        inspect(args, report)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError,
            zipfile.BadZipFile) as error:
        report["error"] = str(error)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{report['status']}: {args.report}")
    if report["status"] != "PASS":
        print(report.get("error", "Unknown inspection failure"))
        return 1
    print(f"{report['catalog']['examples']} examples / {report['catalog']['scripts']} scripts; device unverified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
