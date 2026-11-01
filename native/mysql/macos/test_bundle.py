"""Portable validator regressions; these do not execute macOS native code."""

from pathlib import Path
import struct
import tempfile
import unittest

import bundle


def packed_version(value):
    return (value[0] << 16) | (value[1] << 8) | value[2]


def string_command(command, value, header=24):
    value = value.encode() + b"\0"
    size = (header + len(value) + 7) & ~7
    return struct.pack("<3I", command, size, header) + bytes(header - 12) + value + bytes(size - header - len(value))


def macho(cpu=0x01000007, platform=1, minimum=(10, 15, 0), dependencies=(), rpaths=(), legacy=False):
    if legacy:
        commands = [struct.pack("<4I", 0x24, 16, packed_version(minimum), 0)]
    else:
        commands = [struct.pack("<6I", 0x32, 24, platform, packed_version(minimum), 0, 0)]
    commands.extend(string_command(0xC, item) for item in dependencies)
    commands.extend(string_command(0x8000001C, item, 12) for item in rpaths)
    data = b"".join(commands)
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 6, len(commands), len(data), 0, 0) + data


class NativeValidationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.contents = self.root / "Helper.app/Contents"

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, name, data):
        path = self.contents / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_current_and_legacy_macos_headers(self):
        for legacy in (False, True):
            path = self.write("Frameworks/client.dylib", macho(legacy=legacy))
            self.assertEqual(bundle.validate_target(path, "x86_64", "10.15")["minimums"], [(10, 15, 0)])

    def test_arm64_and_rosetta_architectures_are_separate(self):
        path = self.write("Frameworks/client.dylib", macho(cpu=0x0100000C, minimum=(11, 0, 0)))
        bundle.validate_target(path, "arm64", "11.0")
        with self.assertRaisesRegex(ValueError, "Wrong architecture"):
            bundle.validate_target(path, "x86_64", "11.0")

    def test_newer_sdk_minimum_os_is_rejected(self):
        path = self.write("Frameworks/client.dylib", macho(minimum=(14, 0, 0)))
        with self.assertRaisesRegex(ValueError, "newer OS"):
            bundle.validate_target(path, "x86_64", "10.15")

    def test_ios_binary_is_rejected(self):
        path = self.write("Frameworks/client.dylib", macho(platform=2))
        with self.assertRaisesRegex(ValueError, "Not a macOS"):
            bundle.validate_target(path, "x86_64", "10.15")

    def test_truncated_and_malformed_load_commands_are_rejected(self):
        good = macho()
        oversized = bytearray(good)
        struct.pack_into("<I", oversized, 36, 80)
        for data in (good[:-1], good[:20], bytes(oversized)):
            with self.subTest(data=data):
                path = self.write("Frameworks/client.dylib", data)
                with self.assertRaises(ValueError):
                    bundle.read_macho(path)

    def test_invalid_dylib_string_is_rejected(self):
        data = bytearray(macho(dependencies=("@loader_path/dependency.dylib",)))
        struct.pack_into("<I", data, 32 + 24 + 8, 4)
        path = self.write("Frameworks/client.dylib", data)
        with self.assertRaisesRegex(ValueError, "string offset"):
            bundle.read_macho(path)

    def test_launcher_plugins_and_ffi_use_loader_relative_closure(self):
        self.write("Frameworks/client.dylib", macho(dependencies=("/usr/lib/libSystem.B.dylib",)))
        for name, dependency in (("MacOS/mysqld", "@loader_path/../Frameworks/client.dylib"),
                                 ("PlugIns/plugin.so", "@loader_path/../Frameworks/client.dylib"),
                                 ("Frameworks/bridge.dylib", "@loader_path/client.dylib")):
            self.write(name, macho(dependencies=(dependency,)))
        self.assertEqual(len(bundle.validate_closure(self.contents, "x86_64", "10.15")), 4)

    def test_outer_executable_relative_and_rpath_dependencies_fail_final_validation(self):
        for dependency in ("@executable_path/../Frameworks/client.dylib", "@rpath/client.dylib"):
            self.write("Frameworks/bridge.dylib", macho(dependencies=(dependency,)))
            with self.assertRaisesRegex(ValueError, "Non-loader-relative"):
                bundle.validate_closure(self.contents, "x86_64", "10.15")
        self.write("Frameworks/bridge.dylib", macho(rpaths=("/opt/homebrew/lib",)))
        with self.assertRaisesRegex(ValueError, "RPATH"):
            bundle.validate_closure(self.contents, "x86_64", "10.15")

    def test_dependency_cannot_escape_helper(self):
        (self.root / "external.dylib").write_bytes(macho())
        self.write("Frameworks/bridge.dylib", macho(dependencies=("@loader_path/../../../../external.dylib",)))
        with self.assertRaisesRegex(ValueError, "Unresolved or external"):
            bundle.validate_closure(self.contents, "x86_64", "10.15")

    def test_data_file_is_not_a_native_dependency(self):
        self.write("Frameworks/client.dylib", b"not a library")
        self.write("Frameworks/bridge.dylib", macho(dependencies=("@loader_path/client.dylib",)))
        with self.assertRaisesRegex(ValueError, "not packaged native code"):
            bundle.validate_closure(self.contents, "x86_64", "10.15")

    def test_dependency_resolution_before_relocation(self):
        dependency = self.write("Frameworks/client.dylib", macho())
        loader = self.write("MacOS/mysqld", macho())
        result = bundle.dependency_path("@rpath/client.dylib", loader, self.contents,
                                        ["@executable_path/../Frameworks"])
        self.assertEqual(result, dependency.resolve())

    def test_system_path_prefix_cannot_hide_parent_components(self):
        self.assertTrue(bundle.is_system("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"))
        self.assertFalse(bundle.is_system("/System/Library/../../external.dylib"))


if __name__ == "__main__":
    unittest.main()
