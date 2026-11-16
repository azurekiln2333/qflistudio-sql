#!/usr/bin/env python3
"""Inspect mobile SQLite ELF and archive native packages with portable hashes."""

import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tarfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_android_sqlite(path, abi):
    data = path.read_bytes()
    expected_machine = {"arm64-v8a": 183, "x86_64": 62}[abi]
    if data[:6] != b"\x7fELF\x02\x01" or len(data) < 64:
        raise ValueError("SQLite must be a little-endian ELF64 library")
    kind, machine = struct.unpack_from("<HH", data, 16)
    if kind != 3 or machine != expected_machine:
        raise ValueError("SQLite ELF type or architecture does not match the target")
    offset = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    if size < 56 or offset + size * count > len(data):
        raise ValueError("Invalid ELF program table")
    loads = 0
    for index in range(count):
        entry = offset + index * size
        if struct.unpack_from("<I", data, entry)[0] != 1:
            continue
        loads += 1
        file_offset, address = struct.unpack_from("<QQ", data, entry + 8)
        alignment = struct.unpack_from("<Q", data, entry + 48)[0]
        if alignment < 16384 or file_offset % 16384 != address % 16384:
            raise ValueError("SQLite lacks 16 KiB LOAD compatibility")
    if not loads:
        raise ValueError("SQLite has no LOAD segments")
    symbols = subprocess.check_output(["llvm-nm-18", "--defined-only", "--dynamic", str(path)], text=True)
    for name in ("qfli_sql_execute", "qfli_sql_result_free", "qfli_sql_version"):
        if not any(line.split()[-1:] == [name] for line in symbols.splitlines()):
            raise ValueError(f"Missing SQLite bridge export: {name}")
    dynamic = subprocess.check_output(["llvm-readelf-18", "--dynamic", str(path)], text=True)
    dependencies = re.findall(r"\(NEEDED\).*?\[([^\]]+)\]", dynamic)
    unexpected = set(dependencies) - {"libc.so", "libm.so", "libdl.so"}
    if unexpected:
        raise ValueError(f"Unpackaged SQLite dependencies: {sorted(unexpected)}")


def package(root, destination, target):
    root = root.resolve(strict=True)
    destination.mkdir(parents=True, exist_ok=True)
    manifest = {"format": 1, "target": target, "commit": os.environ.get("GITHUB_SHA"),
                "runId": os.environ.get("GITHUB_RUN_ID"), "files": {},
                "mysql": "8.4.6", "openssl": "3.5.3", "sqlite": "3.50.0"}
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name not in {"SHA256SUMS", "manifest.json"}:
            manifest["files"][path.relative_to(root).as_posix()] = digest(path)
    if not manifest["files"]:
        raise ValueError("Refusing an empty native package")
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    hashes = dict(manifest["files"])
    hashes["manifest.json"] = digest(root / "manifest.json")
    (root / "SHA256SUMS").write_text("".join(f"{value}  {name}\n" for name, value in sorted(hashes.items())), encoding="utf-8", newline="\n")
    archive = destination / f"{target}.tar.gz"
    with tarfile.open(archive, "w:gz") as stream:
        for path in sorted(root.iterdir()):
            stream.add(path, arcname=path.name)
    (destination / "SHA256SUMS").write_text(f"{digest(archive)}  {archive.name}\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    if sys.argv[1] == "check-android-sqlite":
        check_android_sqlite(Path(sys.argv[2]), sys.argv[3])
    elif sys.argv[1] == "package":
        package(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
    else:
        raise SystemExit("Unknown native package command")
