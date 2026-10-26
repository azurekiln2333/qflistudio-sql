"""Regression checks for false package passes and audit-build cleanup."""

import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from inspect_audit_hap import check_catalog, check_names, check_permissions, elf_machine


ROOT = Path(__file__).resolve().parents[2]


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


class AuditBuildCleanupTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is needed for the actual wrapper regression")
    def test_early_metadata_failure_always_releases_build_lock(self):
        for existing_profile in (False, True):
            with self.subTest(existing_profile=existing_profile):
                with tempfile.TemporaryDirectory(prefix="qfli-audit-lock-check-") as directory:
                    fixture = Path(directory)
                    self.assertEqual(fixture.resolve().parent, Path(tempfile.gettempdir()).resolve())
                    (fixture / "tool/ohos").mkdir(parents=True)
                    script = fixture / "tool/ohos/build_audit_hap.ps1"
                    shutil.copy2(ROOT / "tool/ohos/build_audit_hap.ps1", script)
                    (fixture / "target.dart").write_text("void main() {}\n", encoding="utf-8")
                    if existing_profile:
                        (fixture / "ohos").mkdir()
                        (fixture / "ohos/build-profile.json5").write_text("{}", encoding="utf-8")
                    result = subprocess.run(
                        [shutil.which("pwsh"), "-NoProfile", "-File", str(script), "-Target", "target.dart"],
                        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
                    )
                    self.assertNotEqual(result.returncode, 0, "Missing metadata must fail")
                    self.assertFalse((fixture / "build/ohos-audit/.build-lock").exists())
                    self.assertFalse((fixture / "build/ohos-audit/build.json").exists())


if __name__ == "__main__":
    unittest.main()
