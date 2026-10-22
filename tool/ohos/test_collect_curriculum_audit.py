"""Local collector fixtures; these are protocol tests, not device evidence."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).with_name("collect_curriculum_audit.py")
SPEC = importlib.util.spec_from_file_location("collect_curriculum_audit", MODULE)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)
RUN = "fixture-run"
BUILD = "fixture-build"


def fixture_catalogs():
    examples, tutorials = [], []
    for index, engine in enumerate(("sqlite", "mysql"), 1):
        lesson_id = f"lesson-{index}"
        source = f"SELECT 1; -- {engine} 鸿蒙🌏\n"
        lesson = {"id": lesson_id, "code": source, "output": "1",
                  "exercises": [{"answer": "SELECT 1;"}, {"answer": "SELECT 1;"}]}
        tutorials.append({"lessons": [lesson]})
        examples.append({"id": f"example-{index}", "sourceLessonId": lesson_id,
                         "code": source, "expectedOutput": "1",
                         "inputFixtures": {"engine": engine, "exerciseSetup": "-- isolated fixture",
                                           "exerciseExpectedOutputs": '["1", "1"]'}})
    return {"entries": examples}, {"entries": tutorials}


def query(value="1"):
    return {"available": True, "exitCode": 0, "error": None, "sqlState": None,
            "columns": ["value"], "rows": [[value]], "affectedRows": 0, "truncated": False}


def fixture_report():
    manifest = audit.catalog_manifest(*fixture_catalogs())
    records = [{"engine": key[0], "exampleId": key[1], "name": key[2],
                **authored, "status": "pass", "reason": "Matched authored output.",
                "actual": "1", "elapsedMs": 0,
                "nativeResult": {"summary": query(), "statements": [query()]}}
               for key, authored in manifest.items()]
    engines = {engine: {"selected": True, "identityVerified": True,
                        "identity": {"engine": engine, "platform": "ohos", "version": "fixture", "verified": True},
                        "expectedExamples": 1, "expectedScripts": 3, "passedExamples": 1,
                        "failedExamples": 0, "notExecutedExamples": 0, "passedScripts": 3,
                        "failedScripts": 0, "notExecutedScripts": 0, "executedScripts": 3,
                        "countsReconcile": True, "exampleCountsReconcile": True,
                        "timedOut": False, "error": None, "cleanup": {"success": True},
                        "cleanupError": None, "gatePassed": True}
               for engine in ("sqlite", "mysql")}
    return {"formatVersion": 1, "audit": audit.MARKER, "runId": RUN,
            "reportPath": "/data/storage/el2/base/files/fixture/report.json",
            "eventPath": "/data/storage/el2/base/files/fixture/events.jsonl",
            "build": {"buildId": BUILD}, "platform": "ohos", "platformVersion": "fixture only",
            "startedAt": "2026-10-22T01:00:00Z", "finishedAt": "2026-10-22T01:01:00Z",
            "status": "pass", "fatalError": None, "catalogExamples": 2, "catalogScripts": 6,
            "passedScripts": 6, "failedScripts": 0, "notExecutedScripts": 0,
            "catalogGatePassed": True, "deviceGatePassed": True, "engines": engines,
            "records": records, "opaqueFutureField": {"retain": "all evidence"}}


def event(details, sequence=1, kind="REPORT"):
    return {"runId": RUN, "sequence": sequence, "kind": kind,
            "timestamp": "2026-10-22T01:02:00Z", "reportPath": details["reportPath"], "details": details}


def chunk_lines(envelope, size=71):
    source = json.dumps(envelope, ensure_ascii=False)
    chunks = [source[index:index + size] for index in range(0, len(source), size)]
    header = {"runId": envelope["runId"], "sequence": envelope["sequence"],
              "reportPath": envelope["reportPath"], "chunked": True, "parts": len(chunks)}
    lines = [f"10-22 I/flutter: {audit.MARKER} REPORT {json.dumps(header)}"]
    for index, chunk in enumerate(chunks, 1):
        part = {"runId": envelope["runId"], "sequence": envelope["sequence"], "kind": "REPORT",
                "part": index, "parts": len(chunks), "jsonChunk": chunk}
        lines.append(f"10-22 I/flutter: {audit.MARKER} DETAIL {json.dumps(part, ensure_ascii=False)}")
    return lines


def fixture_events(report):
    events = []

    def add(kind, details):
        events.append({"runId": RUN, "sequence": len(events) + 1, "kind": kind,
                       "timestamp": "2026-10-22T01:02:00Z", "reportPath": report["reportPath"], "details": details})

    add("CATALOG", {"examples": 2, "scripts": 6, "selectedEngines": ["sqlite", "mysql"]})
    for record in report["records"]:
        details = {key: record[key] for key in ("engine", "exampleId", "name")}
        add("SCRIPT_START", details)
        add("SCRIPT_PASS", details)
    add("AUDIT_COMPLETE", {"catalogGatePassed": True, "deviceGatePassed": True})
    add("REPORT", report)
    return events


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.examples, self.tutorials = fixture_catalogs()
        self.manifest = audit.catalog_manifest(self.examples, self.tutorials)
        self.report = fixture_report()

    def validate(self, report=None, **overrides):
        options = {"run_id": RUN, "build_id": BUILD, "platform": "ohos",
                   "expected_examples": 2, "expected_scripts": 6, **overrides}
        return audit.validate_report(report or self.report, self.manifest, **options)

    def test_full_records_recomputed_and_preserved(self):
        before = copy.deepcopy(self.report)
        result = self.validate()
        self.assertTrue(result["deviceGatePassed"])
        self.assertEqual(result["engines"]["mysql"]["expectedScripts"], 3)
        self.assertEqual(self.report, before)

    def test_current_shipped_catalog_has_full_126_372_denominator(self):
        root = MODULE.parents[2]
        manifest = audit.catalog_manifest(audit.read_json(root / "assets/content/sql_examples.json"),
                                          audit.read_json(root / "assets/content/sql_tutorials.json"))
        self.assertEqual(len(manifest), 372)
        self.assertEqual(len({key[1] for key in manifest}), 126)
        self.assertEqual(sum(key[0] == "sqlite" for key in manifest), 360)
        self.assertEqual(sum(key[0] == "mysql" for key in manifest), 12)

    def test_unicode_prefixed_out_of_order_chunks_reassemble_exact_event(self):
        envelope = event(self.report, sequence=123)
        lines = chunk_lines(envelope)
        lines[1:] = reversed(lines[1:])
        self.assertEqual(audit.collect_hilog("\n".join(lines), RUN), envelope)

    def test_single_message_report(self):
        envelope = event(self.report)
        line = f"noise {audit.MARKER} REPORT {json.dumps(envelope)}"
        self.assertEqual(audit.collect_hilog(line, RUN), envelope)

    def test_missing_duplicate_conflicting_and_orphan_chunks_rejected(self):
        lines = chunk_lines(event(self.report))
        mutations = [lines[:-1], lines + [lines[1]], lines[1:]]
        part = json.loads(lines[1].split(" DETAIL ", 1)[1])
        part["parts"] += 1
        mutations.append([lines[0], f"{audit.MARKER} DETAIL {json.dumps(part)}", *lines[2:]])
        for captured in mutations:
            with self.subTest(captured=captured[-1][:80]), self.assertRaises(audit.AuditError):
                audit.collect_hilog("\n".join(captured), RUN)

    def test_mixed_run_or_sequence_cannot_supply_missing_part(self):
        for field, value in (("runId", "other-run"), ("sequence", 2)):
            lines = chunk_lines(event(self.report))
            part = json.loads(lines[1].split(" DETAIL ", 1)[1])
            part[field] = value
            lines[1] = f"{audit.MARKER} DETAIL {json.dumps(part)}"
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                audit.collect_hilog("\n".join(lines), RUN)

    def test_envelope_identity_must_match_outer_chunks(self):
        envelope = event(self.report)
        for field, value in (("runId", "other-run"), ("sequence", 2)):
            changed = copy.deepcopy(envelope)
            changed[field] = value
            lines = chunk_lines(changed)
            for index, line in enumerate(lines):
                kind, raw = line.split(f"{audit.MARKER} ", 1)[1].split(" ", 1)
                outer = json.loads(raw)
                outer[field] = envelope[field]
                lines[index] = f"{audit.MARKER} {kind} {json.dumps(outer)}"
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                audit.collect_hilog("\n".join(lines), RUN)

    def test_extra_other_event_kind_at_report_sequence_is_rejected(self):
        lines = chunk_lines(event(self.report))
        part = json.loads(lines[1].split(" DETAIL ", 1)[1])
        part["kind"] = "CATALOG"
        lines.append(f"{audit.MARKER} DETAIL {json.dumps(part)}")
        with self.assertRaises(audit.AuditError):
            audit.collect_hilog("\n".join(lines), RUN)

    def test_multiple_reports_require_sequence_and_duplicate_header_rejected(self):
        first, second = chunk_lines(event(self.report, 5)), chunk_lines(event(self.report, 6))
        captured = "\n".join(first + second)
        with self.assertRaises(audit.AuditError):
            audit.collect_hilog(captured, RUN)
        self.assertEqual(audit.collect_hilog(captured, RUN, 6)["sequence"], 6)
        with self.assertRaises(audit.AuditError):
            audit.collect_hilog("\n".join(first + [first[0]]), RUN)

    def test_report_identity_and_counts_are_explicit(self):
        for field, value in (("runId", "wrong"), ("platform", "windows"),
                             ("catalogExamples", 1), ("catalogScripts", 5), ("passedScripts", 5),
                             ("finishedAt", None), ("status", "running"), ("deviceGatePassed", False)):
            changed = copy.deepcopy(self.report)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                self.validate(changed)
        with self.assertRaises(audit.AuditError):
            self.validate(build_id="different-build")
        with self.assertRaises(audit.AuditError):
            self.validate(expected_scripts=5)

    def test_omitted_duplicated_and_drifted_records_rejected(self):
        variants = []
        missing = copy.deepcopy(self.report)
        missing["records"].pop()
        variants.append(missing)
        duplicate = copy.deepcopy(self.report)
        duplicate["records"][-1] = duplicate["records"][0]
        variants.append(duplicate)
        for field in ("source", "authoredExpected", "actual", "engine"):
            changed = copy.deepcopy(self.report)
            changed["records"][0][field] = "wrong"
            variants.append(changed)
        for changed in variants:
            with self.subTest(changed=changed["records"][0]["name"]), self.assertRaises(audit.AuditError):
                self.validate(changed)

    def test_missing_report_and_engine_error_fields_do_not_mean_clean(self):
        missing_fatal = copy.deepcopy(self.report)
        del missing_fatal["fatalError"]
        with self.assertRaises(audit.AuditError):
            self.validate(missing_fatal)
        missing_error = copy.deepcopy(self.report)
        del missing_error["engines"]["mysql"]["error"]
        with self.assertRaises(audit.AuditError):
            self.validate(missing_error)

    def test_native_success_cannot_hide_unavailable_truncated_sparse_or_wrong_output(self):
        for field, value in (("available", False), ("truncated", True), ("exitCode", 1),
                             ("error", "native failure"), ("rows", [None]), ("rows", [["99"]]),
                             ("rows", [[None, "extra"]])):
            changed = copy.deepcopy(self.report)
            changed["records"][0]["nativeResult"]["statements"][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(audit.AuditError):
                self.validate(changed)

    def test_null_row_does_not_equal_no_rows(self):
        changed = copy.deepcopy(self.report)
        changed["records"][0]["authoredExpected"] = "(no rows)"
        changed["records"][0]["actual"] = ""
        changed["records"][0]["nativeResult"]["statements"][0]["rows"] = [[None]]
        manifest = copy.deepcopy(self.manifest)
        manifest[next(iter(manifest))]["authoredExpected"] = "(no rows)"
        with self.assertRaises(audit.AuditError):
            audit.validate_report(changed, manifest, run_id=RUN, build_id=BUILD, platform="ohos",
                                  expected_examples=2, expected_scripts=6)

    def test_engine_identity_summary_and_cleanup_are_reconciled(self):
        for field, value in (("selected", False), ("timedOut", True), ("identityVerified", False),
                             ("cleanup", {"success": False}), ("passedScripts", 2),
                             ("countsReconcile", False), ("gatePassed", False)):
            changed = copy.deepcopy(self.report)
            changed["engines"]["mysql"][field] = value
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                self.validate(changed)
        for field, value in (("engine", "sqlite"), ("platform", "windows"), ("version", "")):
            changed = copy.deepcopy(self.report)
            changed["engines"]["mysql"]["identity"][field] = value
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                self.validate(changed)

    def test_valid_failed_run_retains_denominator_and_never_upgrades_to_pass(self):
        changed = copy.deepcopy(self.report)
        changed["records"][0].update(status="fail", reason="authored mismatch", actual="99")
        changed["records"][0]["nativeResult"]["statements"][0]["rows"] = [["99"]]
        changed.update(status="fail", passedScripts=5, failedScripts=1, catalogGatePassed=False, deviceGatePassed=False)
        changed["engines"]["sqlite"].update(passedScripts=2, failedScripts=1,
                                                passedExamples=0, failedExamples=1, gatePassed=False)
        result = self.validate(changed)
        self.assertFalse(result["deviceGatePassed"])
        self.assertEqual(result["catalogScripts"], 6)
        self.assertEqual(result["failedScripts"], 1)

    def test_event_history_rejects_sequence_gaps_duplicates_run_and_report_drift(self):
        events = fixture_events(self.report)
        source = "\n".join(json.dumps(item) for item in events)
        recovered = audit.read_events(source, RUN)
        audit.validate_events(recovered, self.report, self.manifest)
        for broken in (events[1:], events + [events[-1]], events[:3] + events[4:]):
            with self.assertRaises(audit.AuditError):
                audit.read_events("\n".join(json.dumps(item) for item in broken), RUN)
        changed = copy.deepcopy(events)
        changed[1]["runId"] = "other"
        with self.assertRaises(audit.AuditError):
            audit.read_events("\n".join(json.dumps(item) for item in changed), RUN)
        changed = copy.deepcopy(self.report)
        changed["opaqueFutureField"] = "mismatched pulled copy"
        with self.assertRaises(audit.AuditError):
            audit.validate_events(events, changed, self.manifest)

    def test_duplicate_json_keys_and_truncated_line_rejected(self):
        with self.assertRaises(audit.AuditError):
            audit.loads('{"runId":"one","runId":"two"}', "fixture")
        with self.assertRaises(audit.AuditError):
            audit.collect_hilog(f'{audit.MARKER} REPORT {{"runId":', RUN)

    def _cli(self, directory, *, report=None, hilog=None, events=None, output="output"):
        root = Path(directory)
        for name, value in (("examples.json", self.examples), ("tutorials.json", self.tutorials)):
            (root / name).write_text(json.dumps(value), encoding="utf-8")
        arguments = [sys.executable, str(MODULE), "--run-id", RUN, "--expected-build-id", BUILD,
                     "--expected-platform", "ohos", "--catalog-examples", str(root / "examples.json"),
                     "--catalog-tutorials", str(root / "tutorials.json"), "--expected-examples", "2",
                     "--expected-scripts", "6", "--output-dir", str(root / output)]
        if report is not None:
            path = root / "input-report.json"
            path.write_text(json.dumps(report), encoding="utf-8-sig")
            arguments += ["--report", str(path)]
        if hilog is not None:
            path = root / "hilog.txt"
            path.write_text(hilog, encoding="utf-8")
            arguments += ["--hilog", str(path)]
        if events is not None:
            path = root / "events.jsonl"
            path.write_text("\n".join(json.dumps(item) for item in events) + "\n", encoding="utf-8")
            arguments += ["--events", str(path)]
        return subprocess.run(arguments, capture_output=True, text=True, encoding="utf-8", check=False)

    def test_cli_report_events_outputs_exact_report_and_machine_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self._cli(directory, report=self.report, events=fixture_events(self.report))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            summary = json.loads(result.stdout)
            self.assertTrue(summary["collectionValidated"])
            self.assertEqual(summary["eventCount"], 15)
            saved = audit.read_json(Path(directory) / "output/report.json")
            self.assertEqual(saved, self.report)
            before = (Path(directory) / "output/report.json").read_bytes()
            again = self._cli(directory, report=self.report)
            self.assertEqual(again.returncode, 2)
            self.assertEqual((Path(directory) / "output/report.json").read_bytes(), before)

    def test_cli_log_only_or_bad_build_fails_but_preserves_all_details(self):
        for mutate in ("persist", "build"):
            with self.subTest(mutate=mutate), tempfile.TemporaryDirectory() as directory:
                envelope = event(copy.deepcopy(self.report))
                if mutate == "persist":
                    envelope.update(logOnly=True, persistError="disk full")
                else:
                    envelope["details"]["build"]["buildId"] = "wrong-build"
                result = self._cli(directory, hilog="\n".join(chunk_lines(envelope)))
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                summary = json.loads(result.stdout)
                self.assertFalse(summary["collectionValidated"])
                self.assertFalse(summary["deviceGatePassed"])
                self.assertEqual(audit.read_json(Path(directory) / "output/report.json"), envelope["details"])

    def test_cli_complete_failed_audit_returns_one_and_keeps_full_denominator(self):
        changed = copy.deepcopy(self.report)
        changed["records"][0].update(status="fail", reason="authored mismatch", actual="99")
        changed["records"][0]["nativeResult"]["statements"][0]["rows"] = [["99"]]
        changed.update(status="fail", passedScripts=5, failedScripts=1, catalogGatePassed=False, deviceGatePassed=False)
        changed["engines"]["sqlite"].update(passedScripts=2, failedScripts=1,
                                                passedExamples=0, failedExamples=1, gatePassed=False)
        with tempfile.TemporaryDirectory() as directory:
            result = self._cli(directory, report=changed)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            summary = json.loads(result.stdout)
            self.assertTrue(summary["collectionValidated"])
            self.assertFalse(summary["deviceGatePassed"])
            self.assertEqual(summary["catalogScripts"], 6)
            self.assertEqual(summary["failedScripts"], 1)
            self.assertEqual(audit.read_json(Path(directory) / "output/report.json"), changed)


if __name__ == "__main__":
    unittest.main()
