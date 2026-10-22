"""Audit actual isolated x86_64 artifacts; this does not execute an OHOS app."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path("/root/qfli-mysql-ohos-x64-1022")
BUILT = ROOT / "ohos-build/qfli-runtime/lib"
PACKAGED = ROOT / "package/libs/x86_64"
PLATFORM = {
    "libc.so", "libc++_shared.so", "libace_napi.z.so", "libhilog_ndk.z.so",
    "libm.so", "libdl.so", "libpthread.so",
}
ENTRIES = {
    "QfliMysqlMain", "qfli_mysql_child_main", "qfli_mysql_record_exit",
    "qfli_mysql_proto_report", "qfli_mysql_proto_ready",
    "qfli_mysql_proto_enter_child_scope", "qfli_mysql_proto_child_exit",
}


def output(*command: str) -> str:
    return subprocess.check_output(command, text=True)


def metadata(path: Path) -> dict:
    info = json.loads(output("llvm-readobj-18", "--needed-libs", "--elf-output-style=JSON", str(path)))[0]
    if info["FileSummary"]["Arch"] != "x86_64":
        raise RuntimeError(f"Wrong ELF architecture: {path}: {info}")
    return info


def main() -> None:
    artifacts = {}
    for name in ("qfli_mysql", "qfli_mysql_server", "qfli_mysql_launcher", "qfli_mysql_server_proto"):
        path = BUILT / f"lib{name}.so"
        info = metadata(path)
        if not (PACKAGED / path.name).is_file():
            raise RuntimeError(f"Missing packaged artifact: {path.name}")
        artifacts[path.name] = {
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "packagedBytes": (PACKAGED / path.name).stat().st_size,
            "packagedSha256": hashlib.sha256((PACKAGED / path.name).read_bytes()).hexdigest(),
            "needed": info["NeededLibraries"],
        }
    for path in PACKAGED.glob("*.so*"):
        for dependency in metadata(path)["NeededLibraries"]:
            if dependency not in PLATFORM and not (PACKAGED / dependency).is_file():
                raise RuntimeError(f"Unresolved runtime dependency: {path.name} -> {dependency}")
    private = BUILT / "libqfli_mysql_server_proto.so"
    if set(artifacts[private.name]["needed"]) != {"libc.so"}:
        raise RuntimeError("Private Oracle server must depend on libc only")
    exports_text = output("llvm-nm-18", "-D", "--defined-only", "--format=posix", str(private))
    exports = {line.split()[0].split("@")[0] for line in exports_text.splitlines()}
    required = {"QfliMysqlMain", "qfli_mysql_child_main", "qfli_mysql_record_exit"}
    if not required <= exports or exports - ENTRIES - {"QFLI_MYSQL_SERVER_1.0"}:
        raise RuntimeError(f"Private Oracle export contract drift: {sorted(exports)}")
    imports = output("llvm-nm-18", "-D", "--undefined-only", str(private))
    if re.search(r"__call_once|__cxa_guard|__gxx_personality|_Unwind_|__cxa_throw|__cxa_allocate_exception|_ZSt|_ZNSt", imports):
        raise RuntimeError("Private server imports external C++/unwind state")
    actual_server = output("llvm-nm-18", "-C", "--defined-only", str(private))
    if "mysqld_main(int, char**)" not in actual_server or "ha_innobase::open(" not in actual_server:
        raise RuntimeError("Built image does not contain the actual Oracle server and InnoDB implementation")
    client = output("llvm-nm-18", "--defined-only", str(BUILT / "libqfli_mysql.so"))
    if "mysql_real_connect" not in client:
        raise RuntimeError("Client image lacks actual Oracle connection implementation")
    manifest = json.loads((ROOT / "package/rawfile/mysql/runtime.json").read_text())
    if manifest["version"] != "8.4.6" or not manifest["files"]:
        raise RuntimeError("Missing actual Oracle8.4.6 resource manifest")
    report = json.dumps({
        "status": "PASS",
        "scope": "actual built x86_64 OHOS ELF and local dependency closure; runtime/device unverified",
        "artifacts": artifacts,
        "privateExports": sorted(exports),
        "resourceFiles": len(manifest["files"]),
        "runtimeVerified": False,
    }, indent=2)
    (ROOT / "closure-report.json").write_text(report + "\n")
    print(report)


if __name__ == "__main__":
    main()
