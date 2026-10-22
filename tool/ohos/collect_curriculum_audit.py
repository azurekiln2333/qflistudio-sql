#!/usr/bin/env python3
"""Collect captured SQL audit evidence. This tool never connects to a device.

Exit codes: 0 complete OHOS gate; 1 valid complete evidence of a failed gate;
2 malformed/incomplete/mismatched evidence or arguments. All parsed report fields
are preserved in report.json, including failures and per-statement native data.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any

MARKER = "QFLI_SQL_CURRICULUM_AUDIT"
ENGINES = ("sqlite", "mysql")


class AuditError(ValueError):
    """Evidence cannot support a reliable audit outcome."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def obj(value: Any, where: str) -> dict:
    require(isinstance(value, dict), f"{where}: expected object")
    return value


def text(value: Any, where: str, *, empty: bool = False) -> str:
    require(isinstance(value, str), f"{where}: expected string")
    require(empty or bool(value.strip()), f"{where}: empty string")
    # Reject unpaired surrogate escapes; real emitter never splits a pair.
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise AuditError(f"{where}: invalid Unicode") from error
    return value


def count(value: Any, where: str, *, positive: bool = False) -> int:
    require(type(value) is int and value >= int(positive), f"{where}: invalid count")
    return value


def boolean(value: Any, where: str) -> bool:
    require(type(value) is bool, f"{where}: expected boolean")
    return value


def _pairs(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def loads(source: str, where: str) -> Any:
    try:
        return json.loads(
            source,
            object_pairs_hook=_pairs,
            parse_constant=lambda value: (_ for _ in ()).throw(
                AuditError(f"{where}: non-finite JSON number {value}")
            ),
        )
    except (json.JSONDecodeError, RecursionError) as error:
        raise AuditError(f"{where}: invalid/truncated JSON: {error}") from error


def read_json(path: Path) -> Any:
    return loads(path.read_text(encoding="utf-8-sig"), str(path))


def normalize(source: str) -> str:
    return "\n".join(line.rstrip() for line in source.strip().split("\n") if line.rstrip())


def catalog_manifest(examples: dict, tutorials: dict) -> dict[tuple[str, str, str], dict]:
    """Reproduce the shipped curriculumCases identity/source contract, not SQL execution."""
    lesson_rows = [
        lesson
        for entry in obj(tutorials, "tutorial catalog").get("entries", [])
        for lesson in obj(entry, "tutorial").get("lessons", [])
    ]
    require(bool(lesson_rows), "Tutorial catalog has no lessons")
    lessons = {}
    for raw in lesson_rows:
        lesson = obj(raw, "lesson")
        key = text(lesson.get("id"), "lesson.id")
        require(key not in lessons, f"Duplicate lesson: {key}")
        lessons[key] = lesson
    rows = obj(examples, "example catalog").get("entries")
    require(isinstance(rows, list) and bool(rows), "Example catalog has no entries")
    ids, covered, result = set(), set(), {}
    for number, raw in enumerate(rows, 1):
        example = obj(raw, "example")
        example_id = text(example.get("id"), "example.id")
        lesson_id = text(example.get("sourceLessonId"), f"{example_id}.sourceLessonId")
        require(example_id not in ids, f"Duplicate example: {example_id}")
        require(lesson_id in lessons and lesson_id not in covered, f"Invalid lesson mapping: {example_id}")
        ids.add(example_id)
        covered.add(lesson_id)
        lesson = lessons[lesson_id]
        source = text(example.get("code"), f"{example_id}.code")
        expected = text(example.get("expectedOutput", example.get("output")), f"{example_id}.expectedOutput")
        require(source == lesson.get("code") and expected == lesson.get("output"), f"Lesson/example drift: {example_id}")
        fixtures = obj(example.get("inputFixtures"), f"{example_id}.inputFixtures")
        engine = fixtures.get("engine")
        require(engine in ENGINES, f"Unknown catalog engine: {engine}")
        setup = text(fixtures.get("exerciseSetup"), f"{example_id}.exerciseSetup", empty=True)
        outputs = loads(text(fixtures.get("exerciseExpectedOutputs"), "exerciseExpectedOutputs"), "exerciseExpectedOutputs")
        exercises = lesson.get("exercises")
        require(isinstance(exercises, list) and isinstance(outputs, list) and len(exercises) == len(outputs) > 0,
                f"Missing authored exercise outputs: {example_id}")
        scripts = [(f"lesson_{number}", source, expected)]
        for index, (exercise, output) in enumerate(zip(exercises, outputs)):
            answer = text(obj(exercise, "exercise").get("answer"), "exercise.answer")
            scripts.append((f"exercise_{number}_{index}", setup.rstrip() + "\n" + answer,
                            text(output, "exercise output")))
        for name, code, output in scripts:
            result[(engine, example_id, name)] = {"source": code, "authoredExpected": output}
    require(covered == set(lessons), "Not every shipped lesson has an example")
    require({key[0] for key in result} == set(ENGINES), "Full catalog must include both SQLite and MySQL")
    return result


def _stamp(value: Any, where: str) -> dt.datetime:
    source = text(value, where)
    try:
        parsed = dt.datetime.fromisoformat(source.replace("Z", "+00:00"))
    except ValueError as error:
        raise AuditError(f"{where}: invalid timestamp") from error
    require(parsed.tzinfo is not None, f"{where}: timezone is missing")
    return parsed


def event_identity(event: dict, run_id: str, *, sequence: int | None = None) -> int:
    require(event.get("runId") == run_id, "Mixed/mismatched event runId")
    seq = count(event.get("sequence"), "event.sequence", positive=True)
    require(sequence is None or seq == sequence, "Mixed/mismatched event sequence")
    text(event.get("kind"), "event.kind")
    text(event.get("reportPath"), "event.reportPath")
    _stamp(event.get("timestamp"), "event.timestamp")
    obj(event.get("details"), "event.details")
    return seq


def collect_hilog(source: str, run_id: str, sequence: int | None = None) -> dict:
    """Select explicitly, never guess the latest run or combine sequence groups."""
    headers, chunks, other_details = {}, {}, set()
    pattern = re.compile(re.escape(MARKER) + r" (REPORT|DETAIL) (.*)$")
    for number, line in enumerate(source.splitlines(), 1):
        match = pattern.search(line)
        if not match:
            continue
        payload = obj(loads(match[2], f"hilog line {number}"), f"hilog line {number}")
        if payload.get("runId") != run_id:
            continue
        seq = count(payload.get("sequence"), "log sequence", positive=True)
        if sequence is not None and seq != sequence:
            continue
        if match[1] == "REPORT":
            require(seq not in headers, f"Duplicate/conflicting REPORT header at sequence {seq}")
            headers[seq] = payload
        elif payload.get("kind") == "REPORT":
            chunks.setdefault(seq, []).append(payload)
        else:
            other_details.add(seq)
    candidates = set(headers) | set(chunks)
    require(bool(candidates), "No REPORT for the explicitly selected run/sequence")
    require(len(candidates) == 1, "Multiple/orphan REPORT sequences; select --sequence explicitly")
    seq = candidates.pop()
    require(seq not in other_details, "Mixed event kinds at the selected REPORT sequence")
    require(seq in headers, "REPORT header is missing")
    header = headers[seq]
    parts = chunks.get(seq, [])
    if header.get("chunked") is True:
        total = count(header.get("parts"), "REPORT.parts", positive=True)
        require(total <= 1_000_000, "Unreasonable REPORT chunk count")
        assembled = {}
        for part in parts:
            require(part.get("runId") == run_id and part.get("sequence") == seq and part.get("kind") == "REPORT",
                    "Mixed REPORT chunk identity")
            require(type(part.get("parts")) is int and part["parts"] == total, "Conflicting REPORT chunk totals")
            index = count(part.get("part"), "DETAIL.part", positive=True)
            require(index <= total, "DETAIL part outside declared range")
            require(index not in assembled, f"Duplicate/conflicting DETAIL part {index}")
            assembled[index] = text(part.get("jsonChunk"), "DETAIL.jsonChunk", empty=True)
        require(len(assembled) == total, f"Missing REPORT chunks: received {len(assembled)}/{total}")
        event = obj(loads("".join(assembled[index] for index in range(1, total + 1)), "reassembled REPORT"), "REPORT")
        require(event.get("reportPath") == header.get("reportPath"), "REPORT path differs from chunk header")
    else:
        require("chunked" not in header and not parts, "Unexpected REPORT chunk/header combination")
        event = header
    event_identity(event, run_id, sequence=seq)
    require(event["kind"] == "REPORT", "Reassembled event is not REPORT")
    return event


def read_events(source: str, run_id: str, sequence: int | None = None) -> list[dict]:
    lines = source.splitlines()
    require(bool(lines), "Empty events.jsonl")
    events = []
    previous_time = None
    for index, line in enumerate(lines, 1):
        require(bool(line.strip()), f"Blank event line {index}")
        event = obj(loads(line, f"event line {index}"), f"event line {index}")
        event_identity(event, run_id, sequence=index)
        stamp = _stamp(event["timestamp"], "event.timestamp")
        require(previous_time is None or stamp >= previous_time, "Event timestamps go backwards")
        previous_time = stamp
        events.append(event)
    require(events[0]["kind"] == "CATALOG", "Event history does not start with CATALOG")
    require(events[-1]["kind"] == "REPORT", "Event history has no final REPORT")
    require(sum(event["kind"] == "REPORT" for event in events) == 1, "Duplicate REPORT event")
    require(sequence is None or events[-1]["sequence"] == sequence, "Final REPORT sequence differs from selection")
    require(len({event["reportPath"] for event in events}) == 1, "Mixed event report paths")
    return events


def query_evidence(raw: Any, where: str, *, success: bool) -> dict:
    query = obj(raw, where)
    for key in ("available", "exitCode", "error", "sqlState", "columns", "rows", "affectedRows", "truncated"):
        require(key in query, f"{where}: missing {key}")
    boolean(query["available"], f"{where}.available")
    boolean(query["truncated"], f"{where}.truncated")
    require(type(query["exitCode"]) is int, f"{where}.exitCode: expected integer")
    count(query["affectedRows"], f"{where}.affectedRows")
    for key in ("error", "sqlState"):
        require(query[key] is None or isinstance(query[key], str), f"{where}.{key}: invalid value")
    columns, rows = query["columns"], query["rows"]
    require(isinstance(columns, list) and all(isinstance(column, str) for column in columns), f"{where}: invalid columns")
    require(isinstance(rows, list) and all(
        isinstance(row, list) and len(row) == len(columns) and all(value is None or isinstance(value, str) for value in row)
        for row in rows), f"{where}: invalid/sparse rows")
    if success:
        require(query["available"] and query["exitCode"] == 0 and query["error"] is None and not query["truncated"],
                f"{where}: claimed PASS has unavailable/failed/truncated native result")
    return query


def validate_report(report: dict, manifest: dict, *, run_id: str, build_id: str,
                    platform: str, expected_examples: int, expected_scripts: int) -> dict:
    required = {"formatVersion", "audit", "runId", "reportPath", "eventPath", "build", "platform",
                "platformVersion", "startedAt", "finishedAt", "status", "fatalError", "catalogExamples",
                "catalogScripts", "passedScripts", "failedScripts", "notExecutedScripts",
                "catalogGatePassed", "deviceGatePassed", "engines", "records"}
    require(required <= set(report), f"Incomplete report fields: {sorted(required - set(report))}")
    require(report.get("formatVersion") == 1 and type(report.get("formatVersion")) is int, "Unsupported report formatVersion")
    require(report.get("audit") == MARKER, "Wrong audit marker")
    require(report.get("runId") == run_id, "Report runId differs from selection")
    text(report.get("reportPath"), "report.reportPath")
    text(report.get("eventPath"), "report.eventPath")
    require(report.get("platform") == platform, "Wrong report platform")
    text(report.get("platformVersion"), "report.platformVersion")
    started = _stamp(report.get("startedAt"), "report.startedAt")
    finished = _stamp(report.get("finishedAt"), "report.finishedAt")
    require(finished >= started, "Report finished before it started")
    build = obj(report.get("build"), "report.build")
    require(build.get("buildId") == build_id, "Wrong report buildId")
    fatal = report.get("fatalError")
    require(fatal is None or isinstance(fatal, str), "Invalid fatalError")
    expected_ids = {key[1] for key in manifest}
    require(len(expected_ids) == expected_examples and len(manifest) == expected_scripts,
            "Expected catalog flags do not match supplied catalog files")
    require(count(report.get("catalogExamples"), "catalogExamples") == expected_examples and
            count(report.get("catalogScripts"), "catalogScripts") == expected_scripts, "Wrong report denominator")
    records = report.get("records")
    require(isinstance(records, list) and len(records) == len(manifest), "Incomplete per-script record denominator")
    by_key = {}
    for index, raw in enumerate(records):
        record = obj(raw, f"record {index}")
        key = tuple(text(record.get(field), f"record.{field}") for field in ("engine", "exampleId", "name"))
        require(key in manifest and key not in by_key, f"Unknown/duplicate script record: {key}")
        require(all(record.get(field) == manifest[key][field] for field in ("source", "authoredExpected")),
                f"Catalog source/output drift: {key}")
        status = record.get("status")
        require(status in ("pass", "fail", "notExecuted"), f"Invalid record status: {key}")
        text(record.get("reason"), f"{key}.reason")
        if status != "notExecuted":
            count(record.get("elapsedMs"), f"{key}.elapsedMs")
        native = record.get("nativeResult")
        if status == "pass" or native is not None:
            native = obj(native, f"{key}.nativeResult")
            query_evidence(native.get("summary"), f"{key}.summary", success=status == "pass")
            statements = native.get("statements")
            require(isinstance(statements, list), f"{key}: missing statement evidence")
            queries = [query_evidence(value, f"{key}.statement {number}", success=status == "pass")
                       for number, value in enumerate(statements)]
            if status == "pass":
                queries = [query for query in queries if query["columns"]]
                require(bool(queries), f"{key}: no query result evidence")
                rows = [row for query in queries for row in query["rows"]]
                expected = record["authoredExpected"]
                if expected.strip() == "(no rows)":
                    require(not rows, f"{key}: NULL/empty rows cannot pass a no-rows expectation")
                    expected = ""
                actual = normalize("\n".join("|".join(value or "" for value in row) for row in rows))
                require(actual == normalize(expected), f"{key}: native output differs from authored output")
                require(record.get("actual") == actual, f"{key}: recorded actual differs from native results")
        by_key[key] = record
    require(set(by_key) == set(manifest), "Incomplete catalog record identity set")
    engines = obj(report.get("engines"), "report.engines")
    require(set(engines) == set(ENGINES), "Full engine denominator is missing/unknown")
    recomputed, gate_failures = {}, []
    for engine in ENGINES:
        state = obj(engines[engine], f"engines.{engine}")
        required_state = {"selected", "identityVerified", "identity", "expectedExamples", "expectedScripts",
                          "passedExamples", "failedExamples", "notExecutedExamples", "passedScripts",
                          "failedScripts", "notExecutedScripts", "executedScripts", "exampleCountsReconcile",
                          "countsReconcile", "timedOut", "error", "cleanup", "cleanupError", "gatePassed"}
        require(required_state <= set(state), f"{engine}: incomplete engine summary fields")
        for field in ("selected", "identityVerified", "timedOut"):
            boolean(state.get(field), f"{engine}.{field}")
        for field in ("error", "cleanupError"):
            require(state.get(field) is None or isinstance(state[field], str), f"{engine}.{field}: invalid value")
        if state["identityVerified"]:
            identity = obj(state.get("identity"), f"{engine}.identity")
            require(state["selected"] and identity.get("engine") == engine and identity.get("verified") is True
                    and identity.get("platform") == platform, f"{engine}: incompatible verified engine identity")
            text(identity.get("version"), f"{engine}.identity.version")
        cleanup = state.get("cleanup")
        if cleanup is not None:
            cleanup = obj(cleanup, f"{engine}.cleanup")
            boolean(cleanup.get("success"), f"{engine}.cleanup.success")
        selected_records = [record for key, record in by_key.items() if key[0] == engine]
        ids = {record["exampleId"] for record in selected_records}
        scripts = {status: sum(record["status"] == status for record in selected_records)
                   for status in ("pass", "fail", "notExecuted")}
        examples = {"pass": 0, "fail": 0, "notExecuted": 0}
        for example_id in ids:
            statuses = [record["status"] for record in selected_records if record["exampleId"] == example_id]
            examples["pass" if all(status == "pass" for status in statuses) else
                     "fail" if "fail" in statuses else "notExecuted"] += 1
        counts = {"expectedExamples": len(ids), "expectedScripts": len(selected_records),
                  "passedExamples": examples["pass"], "failedExamples": examples["fail"],
                  "notExecutedExamples": examples["notExecuted"], "passedScripts": scripts["pass"],
                  "failedScripts": scripts["fail"], "notExecutedScripts": scripts["notExecuted"],
                  "executedScripts": scripts["pass"] + scripts["fail"]}
        for field, value in counts.items():
            require(count(state.get(field), f"{engine}.{field}") == value, f"{engine}: conflicting {field}")
        require(state.get("countsReconcile") is True and state.get("exampleCountsReconcile") is True,
                f"{engine}: counts do not reconcile")
        gate = bool(ids and state["selected"] and state["identityVerified"] and not state["timedOut"]
                    and state.get("error") is None and state.get("cleanupError") is None
                    and cleanup is not None and cleanup["success"] and scripts["pass"] == len(selected_records))
        require(type(state.get("gatePassed")) is bool and state["gatePassed"] == gate, f"{engine}: conflicting gatePassed")
        recomputed[engine] = {**counts, "gatePassed": gate}
        if not gate:
            gate_failures.append(f"{engine}: engine identity/execution/cleanup gate failed")
    totals = {status: sum(record["status"] == status for record in by_key.values())
              for status in ("pass", "fail", "notExecuted")}
    for field, status in (("passedScripts", "pass"), ("failedScripts", "fail"), ("notExecutedScripts", "notExecuted")):
        require(count(report.get(field), field) == totals[status], f"Conflicting report {field}")
    catalog_gate = fatal is None and all(value["gatePassed"] for value in recomputed.values())
    device_gate = platform == "ohos" and catalog_gate
    require(type(report.get("catalogGatePassed")) is bool and report["catalogGatePassed"] == catalog_gate,
            "Conflicting catalogGatePassed")
    require(type(report.get("deviceGatePassed")) is bool and report["deviceGatePassed"] == device_gate,
            "Conflicting deviceGatePassed")
    require(report.get("status") == ("pass" if catalog_gate else "fail"), "Incomplete/conflicting report status")
    if fatal is not None:
        gate_failures.append(f"fatalError: {fatal}")
    if platform != "ohos":
        gate_failures.append("Host execution cannot pass the OHOS device gate")
    return {"catalogExamples": expected_examples, "catalogScripts": expected_scripts,
            "passedScripts": totals["pass"], "failedScripts": totals["fail"], "notExecutedScripts": totals["notExecuted"],
            "engines": recomputed, "catalogGatePassed": catalog_gate,
            "deviceGatePassed": device_gate, "gateFailures": gate_failures}


def validate_events(events: list[dict], report: dict, manifest: dict) -> None:
    require(events[-1]["details"] == report, "Pulled report differs from final event REPORT")
    require(all(event["reportPath"] == report["reportPath"] for event in events), "Event/report path mismatch")
    catalog = events[0]["details"]
    require(catalog.get("examples") == report["catalogExamples"] and catalog.get("scripts") == report["catalogScripts"],
            "CATALOG event denominator mismatch")
    selected = [engine for engine in ENGINES if report["engines"][engine]["selected"]]
    require(isinstance(catalog.get("selectedEngines"), list) and
            len(catalog["selectedEngines"]) == len(set(catalog["selectedEngines"])) and
            set(catalog["selectedEngines"]) == set(selected), "CATALOG selected engine mismatch")
    records = {(record["engine"], record["exampleId"], record["name"]): record for record in report["records"]}
    started, ended, completed = set(), set(), 0
    allowed = {"CATALOG", "IDENTITY", "SCRIPT_START", "SCRIPT_PASS", "SCRIPT_FAIL", "ENGINE_OMITTED",
               "ENGINE_COMPLETE", "AUDIT_COMPLETE", "REPORT"}
    for event in events:
        kind, details = event["kind"], event["details"]
        require(kind in allowed, f"Unknown event kind: {kind}")
        if kind.startswith("SCRIPT_"):
            key = tuple(details.get(field) for field in ("engine", "exampleId", "name"))
            require(key in manifest, f"Unknown event script: {key}")
            if kind == "SCRIPT_START":
                require(key not in started, f"Duplicate SCRIPT_START: {key}")
                started.add(key)
            else:
                require(key in started and key not in ended, f"Missing/duplicate script lifecycle: {key}")
                require(records[key]["status"] == ("pass" if kind == "SCRIPT_PASS" else "fail"), f"Event outcome mismatch: {key}")
                ended.add(key)
        elif kind == "AUDIT_COMPLETE":
            completed += 1
            require(details.get("catalogGatePassed") == report["catalogGatePassed"] and
                    details.get("deviceGatePassed") == report["deviceGatePassed"], "AUDIT_COMPLETE outcome mismatch")
    require(completed == 1, "Missing/duplicate AUDIT_COMPLETE event")
    require(ended == {key for key, record in records.items() if record["status"] != "notExecuted"},
            "Missing per-script completion event")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hilog", type=Path, help="Captured UTF-8 hilog; never reads a live device")
    parser.add_argument("--report", type=Path, help="Pulled report.json")
    parser.add_argument("--events", type=Path, help="Pulled events.jsonl, alone or with --report")
    parser.add_argument("--run-id", required=True, help="Explicit selected runId; no latest-run inference")
    parser.add_argument("--sequence", type=int, help="Explicit REPORT sequence; required if a run has multiple candidates")
    parser.add_argument("--expected-build-id", required=True)
    parser.add_argument("--expected-platform", required=True)
    parser.add_argument("--catalog-examples", required=True, type=Path)
    parser.add_argument("--catalog-tutorials", required=True, type=Path)
    parser.add_argument("--expected-examples", required=True, type=int)
    parser.add_argument("--expected-scripts", required=True, type=int)
    parser.add_argument("--output-dir", required=True, type=Path, help="Fresh local output directory; evidence is never overwritten")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    summary: dict[str, Any] = {"collectorFormatVersion": 1, "runId": args.run_id,
                               "expectedBuildId": args.expected_build_id, "expectedPlatform": args.expected_platform,
                               "collectionValidated": False, "deviceGatePassed": False, "validationErrors": []}
    report, envelope, exit_code = None, None, 2
    outputs = [args.output_dir / name for name in ("summary.json", "report.json", "report-event.json")]
    try:
        require(bool(args.run_id.strip()) and bool(args.expected_build_id.strip()), "runId and buildId must be nonempty")
        require(args.expected_examples > 0 and args.expected_scripts > 0, "Expected counts must be positive")
        require(args.sequence is None or args.sequence > 0, "--sequence must be positive")
        require(args.sequence is None or args.hilog is not None or args.events is not None,
                "--sequence needs --hilog or --events; report.json does not contain an event sequence")
        require(not (args.hilog and (args.report or args.events)) and bool(args.hilog or args.report or args.events),
                "Use --hilog OR --report [--events] OR --events")
        inputs = [path for path in (args.hilog, args.report, args.events, args.catalog_examples, args.catalog_tutorials) if path]
        require(not any(path.exists() for path in outputs), "Output evidence already exists; choose a fresh --output-dir")
        require(not any(output.resolve() == path.resolve() for output in outputs for path in inputs), "Output would overwrite input evidence")
        summary["inputs"] = [{"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in inputs]
        manifest = catalog_manifest(read_json(args.catalog_examples), read_json(args.catalog_tutorials))
        events = None
        if args.hilog:
            envelope = collect_hilog(args.hilog.read_text(encoding="utf-8-sig"), args.run_id, args.sequence)
            report = obj(envelope["details"], "REPORT.details")
        elif args.events:
            events = read_events(args.events.read_text(encoding="utf-8-sig"), args.run_id, args.sequence)
            envelope = events[-1]
            report = obj(envelope["details"], "REPORT.details")
        if args.report:
            report = obj(read_json(args.report), "report")
        require(report is not None, "No report was collected")
        summary.update(validate_report(report, manifest, run_id=args.run_id, build_id=args.expected_build_id,
                                       platform=args.expected_platform, expected_examples=args.expected_examples,
                                       expected_scripts=args.expected_scripts))
        if envelope:
            require(envelope["reportPath"] == report["reportPath"], "REPORT envelope path mismatch")
            require(envelope.get("logOnly", False) is False and not envelope.get("persistError"),
                    "Final REPORT persistence failed (logOnly/persistError); no successful gate accepted")
            summary["reportSequence"] = envelope["sequence"]
        if events is not None:
            validate_events(events, report, manifest)
            summary["eventCount"] = len(events)
        summary["collectionValidated"] = True
        exit_code = 0 if summary["deviceGatePassed"] else 1
    except (ValueError, OSError, UnicodeError, TypeError, KeyError) as error:
        summary["validationErrors"].append(str(error))
        summary["deviceGatePassed"] = False
    summary["exitCode"] = exit_code
    # A malformed collected report is retained for diagnosis, but the separate
    # summary cannot call it validated or promote its embedded PASS claim.
    try:
        require(not any(path.exists() for path in outputs), "Output evidence already exists; refusing overwrite")
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for path, value in ((outputs[1], report), (outputs[2], envelope), (outputs[0], summary)):
            if value is not None:
                with path.open("x", encoding="utf-8", newline="\n") as stream:
                    json.dump(value, stream, ensure_ascii=False, allow_nan=False, indent=2)
                    stream.write("\n")
    except (AuditError, OSError, UnicodeError, ValueError) as error:
        summary["validationErrors"].append(f"Cannot preserve output evidence: {error}")
        summary["collectionValidated"] = False
        summary["deviceGatePassed"] = False
        summary["exitCode"] = exit_code = 2
    print(json.dumps(summary, ensure_ascii=True, allow_nan=False))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
