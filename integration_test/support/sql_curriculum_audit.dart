import 'dart:async';

import 'package:qfli_sql/sql_database.dart';

import 'sql_curriculum_support.dart';

/// A real engine session owns its isolation and timeout retention policy.
abstract interface class CurriculumEngineSession {
  Future<Map<String, Object?>> identify();
  Future<SqlScriptResult> execute(CurriculumScript script);
  void retainAfterTimeout();
  Future<Map<String, Object?>> close();
}

enum CurriculumAuditStatus { pass, fail, notExecuted }

class CurriculumAuditRecord {
  CurriculumAuditRecord(this.engine, this.script);

  final String engine;
  final CurriculumScript script;
  CurriculumAuditStatus status = CurriculumAuditStatus.notExecuted;
  String reason = 'Engine has not been attempted.';
  String? actual;
  Map<String, Object?>? nativeResult;
  int? elapsedMs;

  Map<String, Object?> toJson() => {
    'engine': engine,
    'exampleId': script.exampleId,
    'name': script.name,
    'status': status.name,
    'reason': reason,
    'source': script.source,
    'authoredExpected': script.expected,
    if (actual != null) 'actual': actual,
    if (nativeResult != null) 'nativeResult': nativeResult,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
  };
}

class CurriculumEngineAudit {
  CurriculumEngineAudit(this.engine);

  final String engine;
  bool selected = false;
  bool identityVerified = false;
  bool timedOut = false;
  Map<String, Object?>? identity;
  Map<String, Object?>? cleanup;
  String? error;
  String? cleanupError;
}

/// The denominator is immutable and contains every shipped example and script.
/// Engine filters affect execution only; they never remove denominator entries.
class CurriculumAuditReport {
  CurriculumAuditReport({
    required List<CurriculumCase> cases,
    required this.platform,
    required this.platformVersion,
  }) : cases = List.unmodifiable([
         for (final entry in cases)
           CurriculumCase(
             exampleId: entry.exampleId,
             engine: entry.engine,
             scripts: List.unmodifiable(entry.scripts),
           ),
       ]),
       records = List.unmodifiable([
         for (final entry in cases)
           for (final script in entry.scripts)
             CurriculumAuditRecord(entry.engine, script),
       ]) {
    final keys = <String>{};
    final examples = <String>{};
    for (final entry in cases) {
      if (!const {'sqlite', 'mysql'}.contains(entry.engine) ||
          entry.scripts.isEmpty ||
          entry.exampleId.isEmpty ||
          !examples.add(entry.exampleId)) {
        throw const FormatException('Invalid full-catalog audit denominator.');
      }
      for (final script in entry.scripts) {
        if (script.exampleId != entry.exampleId ||
            script.name.isEmpty ||
            script.source.trim().isEmpty ||
            script.expected.trim().isEmpty ||
            !keys.add('${entry.engine}/${entry.exampleId}/${script.name}')) {
          throw const FormatException('Duplicate or mismatched audit script.');
        }
      }
    }
  }

  final List<CurriculumCase> cases;
  final List<CurriculumAuditRecord> records;
  final String platform;
  final String platformVersion;
  final startedAt = DateTime.now().toUtc();
  DateTime? finishedAt;
  String? fatalError;
  final Map<String, CurriculumEngineAudit> engines = Map.unmodifiable({
    'sqlite': CurriculumEngineAudit('sqlite'),
    'mysql': CurriculumEngineAudit('mysql'),
  });

  Map<String, Object?> engineSummary(String engine) {
    final state = engines[engine]!;
    final expectedCases = cases
        .where((entry) => entry.engine == engine)
        .toList();
    final expectedRecords = records
        .where((entry) => entry.engine == engine)
        .toList();
    final passed = expectedRecords
        .where((r) => r.status == CurriculumAuditStatus.pass)
        .length;
    final failed = expectedRecords
        .where((r) => r.status == CurriculumAuditStatus.fail)
        .length;
    final notExecuted = expectedRecords
        .where((r) => r.status == CurriculumAuditStatus.notExecuted)
        .length;
    var passedExamples = 0;
    var failedExamples = 0;
    var notExecutedExamples = 0;
    for (final entry in expectedCases) {
      final entries = expectedRecords
          .where((record) => record.script.exampleId == entry.exampleId)
          .toList();
      if (entries.length == entry.scripts.length &&
          entries.every(
            (record) => record.status == CurriculumAuditStatus.pass,
          )) {
        passedExamples++;
      } else if (entries.any(
        (record) => record.status == CurriculumAuditStatus.fail,
      )) {
        failedExamples++;
      } else {
        notExecutedExamples++;
      }
    }
    final scriptCountsReconcile =
        passed + failed + notExecuted == expectedRecords.length;
    final exampleCountsReconcile =
        passedExamples + failedExamples + notExecutedExamples ==
        expectedCases.length;
    final gate =
        expectedCases.isNotEmpty &&
        state.selected &&
        state.identityVerified &&
        !state.timedOut &&
        state.error == null &&
        state.cleanupError == null &&
        state.cleanup?['success'] == true &&
        scriptCountsReconcile &&
        exampleCountsReconcile &&
        passed == expectedRecords.length &&
        passedExamples == expectedCases.length &&
        failed == 0 &&
        notExecuted == 0;
    return {
      'selected': state.selected,
      'identityVerified': state.identityVerified,
      'identity': state.identity,
      'expectedExamples': expectedCases.length,
      'expectedScripts': expectedRecords.length,
      'passedExamples': passedExamples,
      'failedExamples': failedExamples,
      'notExecutedExamples': notExecutedExamples,
      'passedScripts': passed,
      'failedScripts': failed,
      'notExecutedScripts': notExecuted,
      'executedScripts': passed + failed,
      'exampleCountsReconcile': exampleCountsReconcile,
      'countsReconcile': scriptCountsReconcile,
      'timedOut': state.timedOut,
      'error': state.error,
      'cleanup': state.cleanup,
      'cleanupError': state.cleanupError,
      'gatePassed': gate,
    };
  }

  bool get catalogGatePassed =>
      finishedAt != null &&
      fatalError == null &&
      cases.isNotEmpty &&
      engines.keys.every(
        (engine) => engineSummary(engine)['gatePassed'] == true,
      ) &&
      records.length ==
          cases.fold<int>(0, (n, entry) => n + entry.scripts.length) &&
      records.every((record) => record.status == CurriculumAuditStatus.pass);

  bool get deviceGatePassed =>
      platform == 'ohos' &&
      platformVersion.trim().isNotEmpty &&
      catalogGatePassed;

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'audit': 'QFLI_SQL_CURRICULUM_AUDIT',
    'platform': platform,
    'platformVersion': platformVersion,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'status': finishedAt == null
        ? 'running'
        : catalogGatePassed
        ? 'pass'
        : 'fail',
    'fatalError': fatalError,
    'catalogExamples': cases.length,
    'catalogScripts': records.length,
    'passedScripts': records
        .where((record) => record.status == CurriculumAuditStatus.pass)
        .length,
    'failedScripts': records
        .where((record) => record.status == CurriculumAuditStatus.fail)
        .length,
    'notExecutedScripts': records
        .where((record) => record.status == CurriculumAuditStatus.notExecuted)
        .length,
    'catalogGatePassed': catalogGatePassed,
    'deviceGatePassed': deviceGatePassed,
    'engines': {
      for (final engine in engines.keys) engine: engineSummary(engine),
    },
    'records': records.map((record) => record.toJson()).toList(),
  };
}

Map<String, Object?> _queryEvidence(SqlQueryResult result) => {
  'available': result.available,
  'exitCode': result.exitCode,
  'error': result.error,
  'sqlState': result.sqlState,
  'columns': result.columns,
  'rows': result.rows,
  'affectedRows': result.affectedRows,
  'truncated': result.truncated,
};

typedef CurriculumAuditCheckpoint =
    Future<void> Function(
      CurriculumAuditReport report,
      String kind,
      Map<String, Object?> details,
    );

/// Continues after ordinary SQL/output failures, but never after a timeout on
/// the same engine: Dart deadlines do not cancel pending native work.
Future<CurriculumAuditReport> runCurriculumAudit({
  required List<CurriculumCase> cases,
  required String platform,
  required String platformVersion,
  required CurriculumEngineSession Function(String engine) sessionFactory,
  Set<String> selectedEngines = const {'sqlite', 'mysql'},
  Duration deadline = const Duration(minutes: 4),
  CurriculumAuditCheckpoint? checkpoint,
}) async {
  final report = CurriculumAuditReport(
    cases: cases,
    platform: platform,
    platformVersion: platformVersion,
  );
  Future<void> save(String kind, Map<String, Object?> details) async {
    try {
      await checkpoint?.call(report, kind, details);
    } on Object catch (error) {
      report.fatalError ??= 'Report checkpoint failed: $error';
      rethrow;
    }
  }

  if (selectedEngines.any((engine) => !report.engines.containsKey(engine))) {
    throw ArgumentError.value(selectedEngines, 'selectedEngines');
  }
  try {
    await save('CATALOG', {
      'examples': cases.length,
      'scripts': report.records.length,
      'selectedEngines': selectedEngines.toList(),
    });
    for (final engine in report.engines.keys) {
      final state = report.engines[engine]!;
      final records = report.records
          .where((record) => record.engine == engine)
          .toList();
      state.selected = selectedEngines.contains(engine);
      if (!state.selected) {
        for (final record in records) {
          record.reason =
              'Engine omitted by explicit execution filter; still required by the full catalog.';
        }
        await save('ENGINE_OMITTED', {
          'engine': engine,
          'scripts': records.length,
        });
        continue;
      }
      if (records.isEmpty) continue;
      CurriculumEngineSession? session;
      try {
        session = sessionFactory(engine);
        final identity = await session.identify().timeout(deadline);
        state.identity = Map.unmodifiable(identity);
        if (identity['engine'] != engine ||
            identity['verified'] != true ||
            identity['platform'] != platform ||
            identity['version'] is! String ||
            (identity['version'] as String).isEmpty) {
          throw StateError('Engine identity is not verified: $identity');
        }
        state.identityVerified = true;
        await save('IDENTITY', {'engine': engine, ...identity});
        for (final record in records) {
          record.reason =
              'Native call in progress; completion is not yet established.';
          await save('SCRIPT_START', {
            'engine': engine,
            'exampleId': record.script.exampleId,
            'name': record.script.name,
          });
          final clock = Stopwatch()..start();
          try {
            final result = await session
                .execute(record.script)
                .timeout(deadline);
            record.nativeResult = {
              'summary': _queryEvidence(result.summary),
              'statements': result.results.map(_queryEvidence).toList(),
            };
            record.actual = verifyCurriculumOutput(result, record.script);
            record.status = CurriculumAuditStatus.pass;
            record.reason = 'Matched the independently authored output.';
          } on TimeoutException catch (error) {
            session.retainAfterTimeout();
            state.timedOut = true;
            state.error = error.toString();
            record.status = CurriculumAuditStatus.fail;
            record.reason =
                'Native deadline expired; operation was not cancelled: $error';
          } on Object catch (error) {
            record.status = CurriculumAuditStatus.fail;
            record.reason = error.toString();
          } finally {
            record.elapsedMs = clock.elapsedMilliseconds;
          }
          if (state.timedOut) {
            for (final pending in records.where(
              (entry) => entry.status == CurriculumAuditStatus.notExecuted,
            )) {
              pending.reason =
                  'Engine aborted after a native timeout; no later call or destructive cleanup attempted.';
            }
          }
          await save('SCRIPT_${record.status.name.toUpperCase()}', {
            'engine': engine,
            'exampleId': record.script.exampleId,
            'name': record.script.name,
            'reason': record.reason,
          });
          if (state.timedOut) break;
        }
      } on TimeoutException catch (error) {
        session?.retainAfterTimeout();
        state.timedOut = true;
        state.error =
            'Engine identity deadline expired; native work was not cancelled: $error';
      } on Object catch (error) {
        state.error = error.toString();
      } finally {
        if (session != null) {
          try {
            state.cleanup = Map.unmodifiable(
              await session.close().timeout(deadline),
            );
            if (state.cleanup?['success'] != true) {
              state.cleanupError = 'Owned runtime cleanup was not confirmed.';
            }
          } on TimeoutException catch (error) {
            session.retainAfterTimeout();
            state.timedOut = true;
            state.cleanupError =
                'Cleanup deadline expired; no further cleanup requested: $error';
          } on Object catch (error) {
            state.cleanupError = error.toString();
          }
        }
      }
      for (final pending in records.where(
        (entry) => entry.status == CurriculumAuditStatus.notExecuted,
      )) {
        pending.reason =
            state.error ?? 'Engine did not execute this required script.';
      }
      await save('ENGINE_COMPLETE', {
        'engine': engine,
        ...report.engineSummary(engine),
      });
      if (report.fatalError != null) break;
    }
  } on Object catch (error) {
    report.fatalError ??= error.toString();
    for (final pending in report.records.where(
      (entry) => entry.status == CurriculumAuditStatus.notExecuted,
    )) {
      pending.reason = 'Audit aborted before execution: ${report.fatalError}';
    }
  }
  report.finishedAt = DateTime.now().toUtc();
  try {
    await save('AUDIT_COMPLETE', {
      'catalogGatePassed': report.catalogGatePassed,
      'deviceGatePassed': report.deviceGatePassed,
    });
  } on Object {
    // The caller still receives the failed full-denominator report if storage
    // becomes unavailable, and can emit it through the independent log path.
  }
  return report;
}
