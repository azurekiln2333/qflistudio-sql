"""Regression checks for false package passes and audit-build cleanup."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

import inspect_audit_hap as inspector

from inspect_audit_hap import (
    AUDIT_SOURCES, check_audit_sources, check_catalog, check_names, check_permissions, elf_machine,
)


ROOT = Path(__file__).resolve().parents[2]


class AuditSourceBindingTest(unittest.TestCase):
    def setUp(self):
        self.sources = {
            relative: f"// current audit source {index}\nvoid source{index}() {{}}\n".encode()
            for index, relative in enumerate(AUDIT_SOURCES)
        }

    def kernel(self, *, omit_path=None, omit_source=None, replacement=None):
        chunks = []
        for relative, source in self.sources.items():
            if relative != omit_path:
                chunks.append(relative.encode())
            if relative != omit_source:
                chunks.append(replacement.get(relative, source) if replacement else source)
        return b"\x00".join(chunks)

    def test_all_five_current_sources_and_hashes_are_required(self):
        bindings = check_audit_sources(self.kernel(), self.sources)
        self.assertEqual([binding["file"] for binding in bindings], list(AUDIT_SOURCES))
        for binding in bindings:
            self.assertEqual(binding["sha256"],
                             hashlib.sha256(self.sources[binding["file"]]).hexdigest())
            self.assertIs(binding["pathMarkerMatch"], True)
            self.assertIs(binding["embeddedSourceMatch"], True)

    def test_crlf_normalization_preserves_raw_source_hashes(self):
        crlf_sources = {relative: source.replace(b"\n", b"\r\n")
                        for relative, source in self.sources.items()}
        bindings = check_audit_sources(self.kernel(), crlf_sources)
        self.assertEqual([binding["sha256"] for binding in bindings],
                         [hashlib.sha256(crlf_sources[relative]).hexdigest()
                          for relative in AUDIT_SOURCES])
        self.assertEqual(check_audit_sources(self.kernel().replace(b"\n", b"\r\n"), self.sources),
                         check_audit_sources(self.kernel(), self.sources))

    def test_each_stale_support_source_is_rejected(self):
        for relative in AUDIT_SOURCES[1:]:
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, relative):
                check_audit_sources(self.kernel(replacement={relative: b"// obsolete helper\n"}),
                                    self.sources)

    def test_each_missing_path_marker_is_rejected_even_with_complete_source(self):
        for relative in AUDIT_SOURCES:
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, "source path"):
                check_audit_sources(self.kernel(omit_path=relative), self.sources)

    def test_each_path_without_its_current_source_is_rejected(self):
        for relative in AUDIT_SOURCES:
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, relative):
                check_audit_sources(self.kernel(omit_source=relative), self.sources)

    def test_missing_source_input_and_empty_source_cannot_pass(self):
        incomplete = dict(self.sources)
        del incomplete[AUDIT_SOURCES[-1]]
        with self.assertRaisesRegex(ValueError, "Exactly five"):
            check_audit_sources(self.kernel(), incomplete)
        empty = {**self.sources, AUDIT_SOURCES[-1]: b""}
        with self.assertRaisesRegex(ValueError, "source is empty"):
            check_audit_sources(self.kernel(), empty)


class PackageGuardTest(unittest.TestCase):
    def setUp(self):
        self.examples = json.loads((ROOT / "assets/content/sql_examples.json").read_text(encoding="utf-8"))
        self.tutorials = json.loads((ROOT / "assets/content/sql_tutorials.json").read_text(encoding="utf-8"))
        self.count = len(self.examples["entries"])
        self.scripts = self.count + sum(len(lesson["exercises"])
                                       for tutorial in self.tutorials["entries"]
                                       for lesson in tutorial["lessons"])

    def check(self, examples):
        return check_catalog(examples, self.tutorials, self.count, self.scripts)

    def test_complete_catalog_and_incorrect_denominator(self):
        self.assertEqual(self.check(self.examples)["scripts"], self.scripts)
        with self.assertRaisesRegex(ValueError, "denominator"):
            check_catalog(self.examples, self.tutorials, self.count, self.scripts + 1)

    def test_uncovered_lesson_is_not_hidden_by_duplicate_mapping(self):
        examples = copy.deepcopy(self.examples)
        examples["entries"][-1]["sourceLessonId"] = examples["entries"][0]["sourceLessonId"]
        with self.assertRaisesRegex(ValueError, "Every lesson"):
            self.check(examples)

    def test_output_drift_and_missing_exercise_expectations_fail(self):
        for change in ("output", "exercise"):
            with self.subTest(change=change):
                examples = copy.deepcopy(self.examples)
                if change == "output":
                    examples["entries"][0]["expectedOutput"] = "incorrect output"
                else:
                    examples["entries"][0]["inputFixtures"]["exerciseExpectedOutputs"] = "[]"
                with self.assertRaises(ValueError):
                    self.check(examples)

    def test_ambiguous_zip_names_and_non_elf_are_rejected(self):
        for names in (["module.json", "module.json"], ["../module.json"], ["/module.json"]):
            with self.subTest(names=names), self.assertRaises(ValueError):
                check_names(names)
        with self.assertRaises(ValueError):
            elf_machine(b"not an ELF image")


class OfflinePermissionTest(unittest.TestCase):
    def test_clipboard_and_local_tcp_are_accepted(self):
        self.assertEqual(
            check_permissions([{"name": "ohos.permission.READ_PASTEBOARD"},
                               {"name": "ohos.permission.INTERNET"}]),
            ["ohos.permission.INTERNET", "ohos.permission.READ_PASTEBOARD"])

    def test_missing_extra_or_duplicate_permission_is_rejected(self):
        for names in ([], ["ohos.permission.INTERNET"],
                      ["ohos.permission.READ_PASTEBOARD"],
                      ["ohos.permission.INTERNET", "ohos.permission.CAMERA"],
                      ["ohos.permission.INTERNET", "ohos.permission.READ_PASTEBOARD",
                       "ohos.permission.CAMERA"],
                      ["ohos.permission.INTERNET", "ohos.permission.INTERNET",
                       "ohos.permission.READ_PASTEBOARD"],
                      ["ohos.permission.INTERNET", "ohos.permission.READ_PASTEBOARD",
                       "ohos.permission.READ_PASTEBOARD"]):
            with self.subTest(names=names), self.assertRaisesRegex(
                    ValueError, "extra, duplicate or missing permissions are forbidden"):
                check_permissions([{"name": name} for name in names])


class InspectionModeTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="qfli-inspection-mode-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "build/ohos-audit"
        self.output.mkdir(parents=True)
        self.sdk = self.root / "sdk"
        for name in ("llvm-strip.exe", "llvm-readelf.exe", "llvm-nm.exe"):
            self.write(self.sdk / "native/llvm/bin" / name, b"inert SDK fixture")
        self.write(self.sdk / "native/sysroot/usr/lib/x86_64-linux-ohos/libc.so", b"fixture")
        self.write(self.sdk / "toolchains/lib/hap-sign-tool.jar", b"inert signing fixture")
        self.metadata = {
            "signed": False, "deviceExecuted": False, "architecture": "ohos-x64",
            "target": inspector.AUDIT_TARGET, "bundleName": "com.azurekiln.qfli.sqlab.fixture",
            "dartDefines": ["QFLI_SQL_CURRICULUM_ENGINES=sqlite,mysql",
                            "QFLI_SQL_CURRICULUM_BUILD_ID=fixture-build"],
        }
        self.payload = {
            "module.json": json.dumps({
                "app": {"bundleName": self.metadata["bundleName"], "debug": True,
                        "buildMode": "debug", "compileSdkVersion": "fixture"},
                "module": {"type": "entry", "mainElement": "EntryAbility",
                           "requestPermissions": [
                               {"name": "ohos.permission.READ_PASTEBOARD"},
                               {"name": "ohos.permission.INTERNET"}]},
            }).encode(),
            "pack.info": json.dumps({"summary": {"app": {
                "bundleName": self.metadata["bundleName"]}}}).encode(),
        }
        for kind in ("examples", "tutorials"):
            relative = f"assets/content/sql_{kind}.json"
            data = (ROOT / relative).read_bytes()
            self.write(self.root / relative, data)
            self.payload[inspector.FLUTTER_ASSETS + relative] = data
        kernel = [b"fixture-build"]
        for index, relative in enumerate(AUDIT_SOURCES):
            data = f"void fixtureSource{index}() {{}}".encode()
            self.write(self.root / relative, data)
            kernel.extend([relative.encode(), data])
        self.payload[inspector.FLUTTER_ASSETS + "kernel_blob.bin"] = b"\x00".join(kernel)
        resources = {f"resource-{index}": b"fixture resource" for index in range(70)}
        resources["runtime.json"] = json.dumps({"version": "8.4.6",
                                              "files": list(resources)}).encode()
        for name, data in resources.items():
            self.write(self.root / "build/mysql-port/package/rawfile/mysql" / name, data)
            self.payload["resources/rawfile/mysql/" + name] = data
        native = bytearray(64)
        native[:6] = b"\x7fELF\x02\x01"
        native[18:20] = (62).to_bytes(2, "little")
        staging = {"artifacts": {}}
        for name in (*inspector.MYSQL_LIBRARIES, "libqfli_sql.so", "libflutter.so",
                     "libc++_shared.so"):
            data = bytes(native) + name.encode()
            self.payload["libs/x86_64/" + name] = data
            if name in inspector.MYSQL_LIBRARIES:
                self.write(self.root / "build/mysql-port/package/libs/x86_64" / name, data)
                staging["artifacts"][name] = {"packagedSha256": inspector.digest(data),
                                             "packagedBytes": len(data)}
        self.write(self.root / "build/mysql-port/package/libs/x86_64/staging.json",
                   json.dumps(staging).encode())
        self.profile = {
            "bundle-info": {"bundle-name": self.metadata["bundleName"], "apl": "normal"},
            "type": "debug", "debug-info": {"device-id-type": "udid", "device-ids": ["fixture"]},
            "validity": {"not-before": 0, "not-after": 9999999999},
        }
        self.calls = []
        self.dynamic_outputs = {}
        self.symbol_outputs = {}
        self.app_result = "verify-app success"
        self.profile_verified = True
        self.refresh()
        file_patch = mock.patch.object(inspector, "__file__",
                                      str(self.root / "tool/ohos/inspect_audit_hap.py"))
        file_patch.start()
        self.addCleanup(file_patch.stop)
        run_patch = mock.patch.object(inspector, "run", side_effect=self.fake_run)
        run_patch.start()
        self.addCleanup(run_patch.stop)

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def refresh(self):
        unsigned = self.output / "sql-audit-unsigned.hap"
        with zipfile.ZipFile(unsigned, "w") as archive:
            for name, data in self.payload.items():
                archive.writestr(name, data)
        self.metadata["unsignedSha256"] = inspector.file_digest(unsigned)
        self.save_metadata()

    def save_metadata(self):
        self.write(self.output / "build.json", json.dumps(self.metadata).encode())

    def sign_fixture(self):
        signed = self.output / "sql-audit-signed.hap"
        shutil.copyfile(self.output / "sql-audit-unsigned.hap", signed)
        with zipfile.ZipFile(signed, "a") as archive:
            archive.writestr(".pages.info", b"fixture code-sign metadata")
        self.metadata.update(signed=True, signedSha256=inspector.file_digest(signed),
                             signingIdentity="fixture SDK identity")
        self.write(self.output / "audit-profile.json", json.dumps(self.profile).encode())
        self.save_metadata()

    def fake_run(self, *arguments):
        self.calls.append(tuple(str(argument) for argument in arguments))
        tool = Path(arguments[0]).name
        if tool == "llvm-strip.exe":
            shutil.copyfile(arguments[2], arguments[4])
            return ""
        if tool == "llvm-readelf.exe":
            if arguments[1] == "--version":
                return "fixture LLVM"
            name = Path(arguments[-1]).name
            return self.dynamic_outputs.get(
                name, "(NEEDED) [libc.so]" if name == "libqfli_mysql_server_proto.so" else "")
        if tool == "llvm-nm.exe":
            if "--defined-only" in arguments:
                return "\n".join(name + " T" for name in inspector.PRIVATE_EXPORTS)
            if "--undefined-only" in arguments:
                return ""
            return self.symbol_outputs.get(Path(arguments[-1]).name, "")
        if tool == "java.exe" and "verify-app" in arguments:
            return self.app_result
        if tool == "java.exe" and "verify-profile" in arguments:
            self.write(Path(arguments[-1]), json.dumps({
                "verifiedPassed": self.profile_verified, "content": self.profile}).encode())
            return "fixture profile result"
        self.fail(f"Unexpected tool call: {arguments}")

    def inspect(self, *, unsigned=True, report=None):
        arguments = argparse.Namespace(sdk=str(self.sdk), jdk=str(self.root / "jdk"),
                                       expected_examples=126, expected_scripts=372)
        if unsigned:
            arguments.unsigned = True
        report = {"status": "FAIL"} if report is None else report
        inspector.inspect(arguments, report)
        return report

    def test_unsigned_checks_complete_package_without_signing_inputs_or_tools(self):
        self.dynamic_outputs["libqfli_sql.so"] = "(NEEDED) [libc.so]"
        self.symbol_outputs.update({"libqfli_sql.so": "fixture_sdk_symbol U",
                                    "libc.so": "fixture_sdk_symbol T"})
        (self.sdk / "toolchains/lib/hap-sign-tool.jar").unlink()
        self.write(self.output / "sql-audit-signed.hap", b"stale signed artifact is ignored")
        report = self.inspect()
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["inspectionMode"], "unsigned")
        self.assertEqual(report["artifact"]["sha256"], self.metadata["unsignedSha256"])
        self.assertEqual(Path(report["artifact"]["path"]).name, "sql-audit-unsigned.hap")
        self.assertEqual((report["catalog"]["examples"], report["catalog"]["scripts"]), (126, 372))
        self.assertEqual(report["manifest"]["permissions"],
                         ["ohos.permission.INTERNET", "ohos.permission.READ_PASTEBOARD"])
        self.assertEqual(len(report["kernel"]["sources"]), 5)
        self.assertIs(report["kernel"]["entryExecutionVerified"], False)
        self.assertIs(report["signature"]["verified"], False)
        self.assertIs(report["signature"]["performed"], False)
        self.assertIs(report["deviceExecuted"], False)
        self.assertNotIn("hap-sign-tool.jar", report["tools"])
        self.assertEqual(report["sdkSymbolClosure"]["libqfli_sql.so"],
                         {"strongImports": 1, "unresolved": []})
        self.assertTrue(any("llvm-strip.exe" in call[0] for call in self.calls))
        self.assertFalse(any("java.exe" in call[0] for call in self.calls))

    def test_omitted_request_permissions_is_rejected_before_manifest_record(self):
        module = json.loads(self.payload["module.json"])
        module["module"].pop("requestPermissions")
        self.payload["module.json"] = json.dumps(module).encode()
        self.refresh()
        report = {"status": "FAIL"}
        with self.assertRaisesRegex(
                ValueError, "extra, duplicate or missing permissions are forbidden"):
            self.inspect(report=report)
        self.assertNotIn("manifest", report)

    def test_unsigned_rejects_contradictory_metadata_before_tools(self):
        original = copy.deepcopy(self.metadata)
        for change in ({"signed": True}, {"signed": 0}, {"signedSha256": None},
                       {"signingIdentity": "stale"}, {"deviceExecuted": True}):
            with self.subTest(change=change):
                self.metadata = {**original, **change}
                self.save_metadata()
                with self.assertRaises(ValueError):
                    self.inspect()
                self.assertEqual(self.calls, [])

    def test_unsigned_hash_and_missing_artifact_never_fall_back_to_signed(self):
        self.sign_fixture()
        self.metadata = {key: value for key, value in self.metadata.items()
                         if key not in {"signedSha256", "signingIdentity"}}
        self.metadata.update(signed=False, unsignedSha256="0" * 64)
        self.save_metadata()
        with self.assertRaisesRegex(ValueError, "Unsigned HAP hash"):
            self.inspect()
        (self.output / "sql-audit-unsigned.hap").unlink()
        with self.assertRaises(FileNotFoundError):
            self.inspect()

    def test_unsigned_retains_catalog_source_native_and_abi_guards(self):
        original = copy.deepcopy(self.payload)
        drift_manifest = json.loads(original["module.json"])
        drift_manifest["module"]["requestPermissions"].append({"name": "ohos.permission.CAMERA"})
        cases = [
            (inspector.FLUTTER_ASSETS + "assets/content/sql_examples.json", b"{}", "Stale catalog"),
            (inspector.FLUTTER_ASSETS + "kernel_blob.bin", b"fixture-build", "source path"),
            ("libs/x86_64/libqfli_mysql.so", original["libs/x86_64/libqfli_sql.so"], "strip transform"),
            ("libs/x86_64/libflutter.so", b"not ELF", "ELF64"),
            ("module.json", json.dumps(drift_manifest).encode(),
             "extra, duplicate or missing permissions are forbidden"),
            ("resources/rawfile/mysql/resource-0", b"stale resource", "Stale Oracle resource"),
            (".pages.info", b"signed marker", "code-sign metadata"),
        ]
        for name, data, error in cases:
            with self.subTest(name=name):
                self.payload = {**original, name: data}
                self.refresh()
                with self.assertRaisesRegex(ValueError, error):
                    self.inspect()
        self.payload = original
        self.metadata["architecture"] = "ohos-arm64"
        self.refresh()
        with self.assertRaisesRegex(ValueError, "x86_64"):
            self.inspect()
        self.metadata["architecture"] = "ohos-x64"
        self.refresh()
        for dynamic, symbols, error in (
                ({"libqfli_sql.so": "(TEXTREL)"}, {}, "Text relocations: libqfli_sql"),
                ({}, {"libqfli_sql.so": "fixture_missing_symbol U"},
                 "Unresolved strong SDK imports: libqfli_sql.*fixture_missing_symbol")):
            with self.subTest(dynamic=dynamic, symbols=symbols):
                self.dynamic_outputs = dynamic
                self.symbol_outputs = symbols
                self.calls.clear()
                with self.assertRaisesRegex(ValueError, error):
                    self.inspect()
                self.assertFalse(any("java.exe" in call[0] for call in self.calls))

    def test_default_signed_mode_refuses_unsigned_record(self):
        with self.assertRaisesRegex(ValueError, "not signed"):
            self.inspect(unsigned=False)
        self.assertEqual(self.calls, [])

    def test_default_signed_mode_requires_real_signature_and_profile_results(self):
        self.sign_fixture()
        report = self.inspect(unsigned=False)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["inspectionMode"], "signed")
        self.assertIs(report["signature"]["verified"], True)
        self.assertTrue(any("verify-app" in call for call in self.calls))
        self.assertTrue(any("verify-profile" in call for call in self.calls))
        self.app_result = "verification failed"
        with self.assertRaisesRegex(ValueError, "did not confirm"):
            self.inspect(unsigned=False)
        self.app_result = "verify-app success"
        self.profile_verified = False
        with self.assertRaisesRegex(ValueError, "Profile signature verification failed"):
            self.inspect(unsigned=False)

    def test_default_signed_mode_preserves_hash_and_zip_payload_binding(self):
        self.sign_fixture()
        signed = self.output / "sql-audit-signed.hap"
        self.metadata["signedSha256"] = "0" * 64
        self.save_metadata()
        with self.assertRaisesRegex(ValueError, "Signed HAP hash"):
            self.inspect(unsigned=False)
        with zipfile.ZipFile(signed, "w") as archive:
            for name, data in {**self.payload, "pack.info": b"changed payload",
                               ".pages.info": b"fixture"}.items():
                archive.writestr(name, data)
        self.metadata["signedSha256"] = inspector.file_digest(signed)
        self.save_metadata()
        with self.assertRaisesRegex(ValueError, "Signing changed ZIP payload: pack.info"):
            self.inspect(unsigned=False)
        original_signed = {**self.payload, ".pages.info": b"fixture"}
        for change in ("added", "removed", "missing-pages"):
            with self.subTest(change=change):
                payload = dict(original_signed)
                if change == "added":
                    payload["unexpected-entry"] = b"unexpected"
                else:
                    del payload["pack.info" if change == "removed" else ".pages.info"]
                with zipfile.ZipFile(signed, "w") as archive:
                    for name, data in payload.items():
                        archive.writestr(name, data)
                self.metadata["signedSha256"] = inspector.file_digest(signed)
                self.save_metadata()
                self.calls.clear()
                with self.assertRaisesRegex(ValueError, "Signing changed ZIP entries"):
                    self.inspect(unsigned=False)
                self.assertFalse(any("java.exe" in call[0] for call in self.calls))

    def test_cli_defaults_keep_denominators_and_separate_report_paths(self):
        for options, filename, mode in (([], "inspection.json", "signed"),
                                        (["--unsigned"], "inspection-unsigned.json", "unsigned")):
            with self.subTest(mode=mode):
                def fake_inspect(arguments, report):
                    self.assertEqual(arguments.expected_examples, 126)
                    self.assertEqual(arguments.expected_scripts, 372)
                    self.assertEqual(arguments.unsigned, mode == "unsigned")
                    report.update(status="PASS", catalog={"examples": 126, "scripts": 372})
                with mock.patch("sys.argv", ["inspect_audit_hap.py", *options]), \
                        mock.patch.object(inspector, "inspect", side_effect=fake_inspect), \
                        mock.patch("builtins.print"):
                    self.assertEqual(inspector.main(), 0)
                report = inspector.read_json(self.output / filename)
                self.assertEqual(report["inspectionMode"], mode)
                self.assertIs(report["deviceExecuted"], False)
        defaults = {name: (self.output / name).read_bytes()
                    for name in ("inspection.json", "inspection-unsigned.json")}
        self.metadata["unsignedSha256"] = "0" * 64
        self.save_metadata()
        for options, mode, error in (
                ([], "signed", "Build record is not signed"),
                (["--unsigned"], "unsigned", "Unsigned HAP hash differs from build record")):
            with self.subTest(mode=mode, outcome="failure"):
                destination = self.root / "failure-reports" / (mode + ".json")
                with mock.patch("sys.argv", ["inspect_audit_hap.py", *options,
                                             "--report", str(destination)]), \
                        mock.patch("builtins.print") as printed:
                    self.assertEqual(inspector.main(), 1)
                report = inspector.read_json(destination)
                self.assertEqual(report["status"], "FAIL")
                self.assertEqual(report["error"], error)
                self.assertEqual(report["inspectionMode"], mode)
                self.assertIs(report["deviceExecuted"], False)
                printed.assert_any_call(f"FAIL: {destination}")
                printed.assert_any_call(error)
                self.assertEqual(self.calls, [])
        for name, data in defaults.items():
            self.assertEqual((self.output / name).read_bytes(), data)


class AuditBuildCleanupTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is needed for the actual wrapper regression")
    def test_early_metadata_failure_always_releases_build_lock(self):
        from test_build_audit_hap import create_toolchain_fixture, fixture_environment

        for existing_profile in (False, True):
            with self.subTest(existing_profile=existing_profile):
                with tempfile.TemporaryDirectory(prefix="qfli-audit-lock-check-") as directory:
                    fixture = Path(directory)
                    self.assertEqual(fixture.resolve().parent, Path(tempfile.gettempdir()).resolve())
                    (fixture / "tool/ohos").mkdir(parents=True)
                    script = fixture / "tool/ohos/build_audit_hap.ps1"
                    shutil.copy2(ROOT / "tool/ohos/build_audit_hap.ps1", script)
                    (fixture / "target.dart").write_text("void main() {}\n", encoding="utf-8")
                    flutter = fixture / "unused-flutter-control.ps1"
                    flutter.write_text("throw 'Flutter must not run before metadata is read'\n",
                                       encoding="utf-8")
                    dev_eco = create_toolchain_fixture(fixture)
                    parser = fixture / "unused-json5-control.cjs"
                    parser.write_text("throw new Error('Node must not run before metadata is read');\n",
                                      encoding="utf-8")
                    environment = fixture_environment(fixture)
                    if existing_profile:
                        (fixture / "ohos").mkdir()
                        (fixture / "ohos/build-profile.json5").write_text("{}", encoding="utf-8")
                    result = subprocess.run(
                        [shutil.which("pwsh"), "-NoProfile", "-File", str(script),
                         "-Target", "target.dart", "-Flutter", str(flutter),
                         "-DevEcoHome", str(dev_eco), "-Json5Module", str(parser)],
                        env=environment,
                        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
                    )
                    self.assertNotEqual(result.returncode, 0, "Missing metadata must fail")
                    missing = "app.json5" if existing_profile else "build-profile.json5"
                    self.assertIn(missing, result.stdout + result.stderr)
                    output = fixture / "build/ohos-audit"
                    self.assertTrue(output.is_dir(), "Preflight must reach build-lock acquisition")
                    for name in (".build-lock", "build.json", "build.log"):
                        self.assertFalse((output / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
