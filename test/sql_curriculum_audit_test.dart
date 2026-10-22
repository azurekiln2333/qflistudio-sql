import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_database.dart';

import '../integration_test/support/sql_curriculum_audit.dart';
import '../integration_test/support/sql_curriculum_runtime.dart';
import '../integration_test/support/sql_curriculum_store.dart';
import '../integration_test/support/sql_curriculum_support.dart';

List<CurriculumCase> _cases() => [
  CurriculumCase(
    exampleId: 'sqlite-example',
    engine: 'sqlite',
    scripts: [
      for (var index = 0; index < 3; index++)
        _script('s$index', 'sqlite-example'),
    ],
  ),
  CurriculumCase(
    exampleId: 'mysql-example',
    engine: 'mysql',
    scripts: [
      for (var index = 0; index < 2; index++)
        _script('m$index', 'mysql-example'),
    ],
  ),
];

CurriculumScript _script(String name, String exampleId) => CurriculumScript(
  name: name,
  exampleId: exampleId,
  source: 'SELECT 1;',
  expected: '1',
);

SqlScriptResult _result([String value = '1']) {
  final query = SqlQueryResult(
    available: true,
    exitCode: 0,
    columns: const ['value'],
    rows: [
      [value],
    ],
    affectedRows: 0,
    truncated: false,
  );
  return SqlScriptResult(summary: query, results: [query]);
}

class _Session implements CurriculumEngineSession {
  _Session(this.engine);

  final String engine;
  Map<String, Object?>? identity;
  Future<Map<String, Object?>> Function()? identifyOperation;
  Future<SqlScriptResult> Function(CurriculumScript)? executeOperation;
  Future<Map<String, Object?>> Function()? closeOperation;
  final calls = <String>[];
  bool retained = false;
  bool? retainedWhenClosed;

  @override
  Future<Map<String, Object?>> identify() async {
    calls.add('identify');
    return identifyOperation != null
        ? await identifyOperation!()
        : identity ??
              {
                'engine': engine,
                'version': engine == 'sqlite' ? '3.50.0' : '8.4.6',
                'platform': 'ohos',
                'verified': true,
              };
  }

  @override
  Future<SqlScriptResult> execute(CurriculumScript script) async {
    calls.add(script.name);
    return executeOperation != null
        ? await executeOperation!(script)
        : _result();
  }

  @override
  void retainAfterTimeout() {
    calls.add('retain');
    retained = true;
  }

  @override
  Future<Map<String, Object?>> close() async {
    calls.add('close');
    retainedWhenClosed = retained;
    return closeOperation != null
        ? await closeOperation!()
        : {'success': !retained, 'retained': retained};
  }
}

Future<CurriculumAuditReport> _run(
  Map<String, _Session> sessions, {
  Set<String> selected = const {'sqlite', 'mysql'},
  Duration deadline = const Duration(seconds: 1),
  CurriculumAuditCheckpoint? checkpoint,
  String platform = 'ohos',
  String platformVersion = 'OHOS test identity',
}) => runCurriculumAudit(
  cases: _cases(),
  platform: platform,
  platformVersion: platformVersion,
  sessionFactory: (engine) => sessions[engine]!,
  selectedEngines: selected,
  deadline: deadline,
  checkpoint: checkpoint,
);

Map<String, _Session> _sessions() => {
  'sqlite': _Session('sqlite'),
  'mysql': _Session('mysql'),
};

void main() {
  test(
    'complete denominator, native evidence and before/after checkpoints reconcile',
    () async {
      final sessions = _sessions();
      final starts = <String>[];
      final completions = <String>[];
      final report = await _run(
        sessions,
        checkpoint: (current, kind, details) async {
          expect(current.records, hasLength(5));
          if (kind == 'SCRIPT_START') {
            starts.add(details['name']! as String);
            final record = current.records.singleWhere(
              (record) => record.script.name == details['name'],
            );
            expect(record.status, CurriculumAuditStatus.notExecuted);
          }
          if (kind == 'SCRIPT_PASS') {
            completions.add(details['name']! as String);
          }
        },
      );
      expect(starts, ['s0', 's1', 's2', 'm0', 'm1']);
      expect(completions, starts);
      expect(report.catalogGatePassed, isTrue);
      expect(report.deviceGatePassed, isTrue);
      expect(
        report.engineSummary('sqlite'),
        containsPair('expectedScripts', 3),
      );
      expect(report.engineSummary('mysql'), containsPair('expectedScripts', 2));
      for (final engine in sessions.keys) {
        expect(
          report.engineSummary(engine),
          containsPair('countsReconcile', true),
        );
        expect(report.engineSummary(engine), containsPair('passedExamples', 1));
      }
      expect(report.toJson()['notExecutedScripts'], 0);
      expect(
        report.records.first.nativeResult!['summary'],
        containsPair('rows', [
          ['1'],
        ]),
      );
      expect(jsonDecode(jsonEncode(report.toJson()))['catalogScripts'], 5);
    },
  );

  for (final selected in <Set<String>>[
    {'sqlite'},
    {},
  ]) {
    test(
      'execution filter $selected preserves omitted-engine denominator and fails gate',
      () async {
        final sessions = _sessions();
        final report = await _run(sessions, selected: selected);
        expect(report.records, hasLength(5));
        expect(report.cases, hasLength(2));
        expect(report.catalogGatePassed, isFalse);
        expect(report.deviceGatePassed, isFalse);
        expect(sessions['mysql']!.calls, isEmpty);
        expect(
          report.engineSummary('mysql'),
          containsPair('expectedScripts', 2),
        );
        expect(
          report.engineSummary('mysql'),
          containsPair('notExecutedScripts', 2),
        );
        expect(
          report.records
              .where((record) => record.engine == 'mysql')
              .every((record) => record.reason.contains('omitted')),
          isTrue,
        );
      },
    );
  }

  test(
    'output mismatch and ordinary SQL exception continue both engines',
    () async {
      final sessions = _sessions();
      sessions['sqlite']!.executeOperation = (script) async {
        if (script.name == 's0') return _result('99');
        if (script.name == 's1') throw StateError('ordinary SQL failure');
        return _result();
      };
      final report = await _run(sessions);
      expect(sessions['sqlite']!.calls, [
        'identify',
        's0',
        's1',
        's2',
        'close',
      ]);
      expect(sessions['mysql']!.calls, ['identify', 'm0', 'm1', 'close']);
      expect(report.records.map((record) => record.status), [
        CurriculumAuditStatus.fail,
        CurriculumAuditStatus.fail,
        CurriculumAuditStatus.pass,
        CurriculumAuditStatus.pass,
        CurriculumAuditStatus.pass,
      ]);
      expect(report.records.first.reason, contains('actual "99"'));
      expect(
        report.records.first.nativeResult!['summary'],
        containsPair('rows', [
          ['99'],
        ]),
      );
      expect(report.engineSummary('sqlite'), containsPair('failedScripts', 2));
      expect(report.engineSummary('sqlite'), containsPair('passedExamples', 0));
      expect(report.deviceGatePassed, isFalse);
    },
  );

  test(
    'script timeout aborts that engine, retains roots and leaves pending scripts explicit',
    () async {
      final pending = Completer<SqlScriptResult>();
      final sessions = _sessions();
      sessions['sqlite']!.executeOperation = (_) => pending.future;
      final report = await _run(
        sessions,
        deadline: const Duration(milliseconds: 10),
      );
      expect(sessions['sqlite']!.calls, ['identify', 's0', 'retain', 'close']);
      expect(sessions['sqlite']!.retainedWhenClosed, isTrue);
      expect(report.engineSummary('sqlite'), containsPair('failedScripts', 1));
      expect(
        report.engineSummary('sqlite'),
        containsPair('notExecutedScripts', 2),
      );
      expect(report.engineSummary('mysql'), containsPair('passedScripts', 2));
      expect(report.deviceGatePassed, isFalse);
      pending.complete(_result());
      await Future<void>.delayed(Duration.zero);
      expect(sessions['sqlite']!.calls, ['identify', 's0', 'retain', 'close']);
      expect(report.records.first.status, CurriculumAuditStatus.fail);
    },
  );

  test(
    'identity timeout executes no scripts and retains before closing',
    () async {
      final sessions = _sessions();
      sessions['sqlite']!.identifyOperation = () =>
          Completer<Map<String, Object?>>().future;
      final report = await _run(
        sessions,
        deadline: const Duration(milliseconds: 10),
      );
      expect(sessions['sqlite']!.calls, ['identify', 'retain', 'close']);
      expect(sessions['sqlite']!.retainedWhenClosed, isTrue);
      expect(
        report.engineSummary('sqlite'),
        containsPair('notExecutedScripts', 3),
      );
      expect(report.engineSummary('mysql'), containsPair('passedScripts', 2));
      expect(report.deviceGatePassed, isFalse);
    },
  );

  for (final invalid in <Map<String, Object?>>[
    {'engine': 'sqlite', 'version': '', 'verified': true, 'platform': 'ohos'},
    {
      'engine': 'sqlite',
      'version': '3.50.0',
      'verified': false,
      'platform': 'ohos',
    },
    {
      'engine': 'mysql',
      'version': '3.50.0',
      'verified': true,
      'platform': 'ohos',
    },
    {
      'engine': 'sqlite',
      'version': '3.50.0',
      'verified': true,
      'platform': 'windows',
    },
    {'engine': 'sqlite', 'version': '3.50.0', 'verified': true},
  ]) {
    test(
      'missing or incompatible engine/platform identity cannot pass: $invalid',
      () async {
        final sessions = _sessions();
        sessions['sqlite']!.identity = invalid;
        final report = await _run(sessions);
        expect(sessions['sqlite']!.calls, ['identify', 'close']);
        expect(
          report.engineSummary('sqlite'),
          containsPair('identityVerified', false),
        );
        expect(
          report.engineSummary('sqlite'),
          containsPair('notExecutedScripts', 3),
        );
        expect(report.deviceGatePassed, isFalse);
      },
    );
  }

  test(
    'session construction failure preserves full counts and continues next engine',
    () async {
      final mysql = _Session('mysql');
      final report = await runCurriculumAudit(
        cases: _cases(),
        platform: 'ohos',
        platformVersion: 'OHOS test',
        sessionFactory: (engine) {
          if (engine == 'sqlite') {
            throw StateError('native library unavailable');
          }
          return mysql;
        },
      );
      expect(
        report.engineSummary('sqlite'),
        containsPair('notExecutedScripts', 3),
      );
      expect(report.engineSummary('mysql'), containsPair('passedScripts', 2));
      expect(report.deviceGatePassed, isFalse);
    },
  );

  for (final cleanup in ['unconfirmed', 'exception', 'timeout']) {
    test('cleanup $cleanup fails gate despite all scripts passing', () async {
      final sessions = _sessions();
      sessions['sqlite']!.closeOperation = () async {
        if (cleanup == 'exception') throw StateError('owned cleanup failed');
        if (cleanup == 'timeout') {
          return Completer<Map<String, Object?>>().future;
        }
        return {'success': false};
      };
      final report = await _run(
        sessions,
        deadline: const Duration(milliseconds: 10),
      );
      expect(
        report.records.every(
          (record) => record.status == CurriculumAuditStatus.pass,
        ),
        isTrue,
      );
      expect(report.engines['sqlite']!.cleanupError, isNotNull);
      expect(report.deviceGatePassed, isFalse);
      if (cleanup == 'timeout') expect(sessions['sqlite']!.retained, isTrue);
    });
  }

  test(
    'lost checkpoint stops further SQL and still returns full failed report',
    () async {
      final sessions = _sessions();
      final report = await _run(
        sessions,
        checkpoint: (_, kind, _) async {
          if (kind == 'SCRIPT_START') {
            throw const FileSystemException('storage unavailable');
          }
        },
      );
      expect(sessions['sqlite']!.calls, ['identify', 'close']);
      expect(sessions['mysql']!.calls, isEmpty);
      expect(report.records, hasLength(5));
      expect(
        report.records.every(
          (record) => record.status == CurriculumAuditStatus.notExecuted,
        ),
        isTrue,
      );
      expect(report.fatalError, contains('checkpoint failed'));
      expect(report.deviceGatePassed, isFalse);
    },
  );

  test(
    'persistent storage failure also cannot escape as a successful audit',
    () async {
      final report = await _run(
        _sessions(),
        checkpoint: (_, _, _) async {
          throw const FileSystemException('disk full');
        },
      );
      expect(report.finishedAt, isNotNull);
      expect(report.records, hasLength(5));
      expect(report.fatalError, contains('disk full'));
      expect(report.deviceGatePassed, isFalse);
    },
  );

  test(
    'platform and complete engine denominator are required for OHOS gate',
    () async {
      final sessions = _sessions();
      for (final session in sessions.values) {
        session.identity = {
          'engine': session.engine,
          'version': 'test version',
          'platform': 'windows',
          'verified': true,
        };
      }
      final host = await _run(sessions, platform: 'windows');
      expect(host.catalogGatePassed, isTrue);
      expect(host.deviceGatePassed, isFalse);
      final missingVersion = await _run(_sessions(), platformVersion: '');
      expect(missingVersion.catalogGatePassed, isTrue);
      expect(missingVersion.deviceGatePassed, isFalse);
      final sqliteOnly = await runCurriculumAudit(
        cases: [_cases().first],
        platform: 'ohos',
        platformVersion: 'OHOS test',
        sessionFactory: (_) => _Session('sqlite'),
      );
      expect(sqliteOnly.catalogGatePassed, isFalse);
      expect(sqliteOnly.deviceGatePassed, isFalse);
    },
  );

  test('denominator validates identity and freezes input collections', () {
    final cases = _cases();
    final report = CurriculumAuditReport(
      cases: cases,
      platform: 'ohos',
      platformVersion: 'test',
    );
    cases.first.scripts.clear();
    cases.clear();
    expect(report.cases.first.scripts, hasLength(3));
    expect(report.records, hasLength(5));
    expect(() => report.records.clear(), throwsUnsupportedError);
    expect(() => report.engines.clear(), throwsUnsupportedError);
    expect(() => report.cases.first.scripts.clear(), throwsUnsupportedError);
    expect(
      () => CurriculumAuditReport(
        cases: [_cases().first, _cases().first],
        platform: 'ohos',
        platformVersion: 'test',
      ),
      throwsFormatException,
    );
    expect(
      () => CurriculumAuditReport(
        cases: [
          CurriculumCase(
            exampleId: 'wrong',
            engine: 'sqlite',
            scripts: [_script('s', 'different')],
          ),
        ],
        platform: 'ohos',
        platformVersion: 'test',
      ),
      throwsFormatException,
    );
    final empty = CurriculumAuditReport(
      cases: [],
      platform: 'ohos',
      platformVersion: 'test',
    );
    empty.finishedAt = DateTime.now().toUtc();
    expect(empty.deviceGatePassed, isFalse);
  });

  final library =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      'native/build/${Platform.operatingSystem}/'
          '${Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so'}';
  test(
    'real bundled session checks dense result sets and a fresh memory database per script',
    () async {
      final session = SqliteCurriculumSession();
      final identity = await session.identify();
      expect(identity['platform'], Platform.operatingSystem);
      expect(identity['denseResultSetSmoke'], [
        [
          ['1'],
        ],
        [
          ['2'],
        ],
      ]);
      const seed = CurriculumScript(
        name: 'seed',
        exampleId: 'host-smoke',
        source:
            'CREATE TABLE audit_fresh(id INTEGER); INSERT INTO audit_fresh VALUES(1); SELECT id FROM audit_fresh;',
        expected: '1',
      );
      verifyCurriculumOutput(await session.execute(seed), seed);
      const fresh = CurriculumScript(
        name: 'fresh',
        exampleId: 'host-smoke',
        source: "SELECT COUNT(*) FROM sqlite_schema WHERE name='audit_fresh';",
        expected: '0',
      );
      verifyCurriculumOutput(await session.execute(fresh), fresh);
      expect(await session.close(), containsPair('success', true));
    },
    skip: !File(library).existsSync()
        ? 'Actual bundled SQLite library unavailable; no native pass claimed.'
        : false,
  );

  test(
    'durable unique reports and numbered Unicode chunks reconstruct exact JSON',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'qfli-audit-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final lines = <String>[];
      final store = await CurriculumAuditStore.create(
        storage: temporary,
        writeLog: lines.add,
      );
      final second = await CurriculumAuditStore.create(
        storage: temporary,
        writeLog: (_) {},
      );
      expect(store.directory.path, isNot(second.directory.path));
      final cases = _cases();
      cases[0].scripts.add(
        CurriculumScript(
          name: 'unicode',
          exampleId: 'sqlite-example',
          source: "SELECT '${List.filled(1000, '鸿蒙🌏').join()}';",
          expected: '1',
        ),
      );
      final sessions = _sessions();
      final report = await runCurriculumAudit(
        cases: cases,
        platform: 'ohos',
        platformVersion: 'OHOS test',
        sessionFactory: (engine) => sessions[engine]!,
        checkpoint: store.checkpoint,
      );
      await store.emitReport(report);
      final saved = jsonDecode(await store.reportFile.readAsString()) as Map;
      expect(saved['catalogScripts'], 6);
      expect(saved['deviceGatePassed'], isTrue);
      final events = (await store.eventFile.readAsLines())
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(events.last['kind'], 'REPORT');
      expect(
        events.where((event) => event['kind'] == 'SCRIPT_START'),
        hasLength(6),
      );
      expect(
        events.where((event) => event['kind'] == 'SCRIPT_PASS'),
        hasLength(6),
      );
      expect(
        events.map((event) => event['sequence']),
        orderedEquals(List.generate(events.length, (index) => index + 1)),
      );
      final details = lines
          .where((line) => line.startsWith('$curriculumAuditMarker DETAIL '))
          .map(
            (line) =>
                jsonDecode(
                      line.substring('$curriculumAuditMarker DETAIL '.length),
                    )
                    as Map,
          )
          .where((chunk) => chunk['kind'] == 'REPORT')
          .toList();
      expect(details, isNotEmpty);
      expect(details.length, details.first['parts']);
      expect(
        details.map((chunk) => chunk['part']),
        orderedEquals(List.generate(details.length, (index) => index + 1)),
      );
      final recovered =
          jsonDecode(
                details.map((chunk) => chunk['jsonChunk'] as String).join(),
              )
              as Map;
      expect((recovered['details'] as Map)['records'], saved['records']);
      expect(lines.every((line) => utf8.encode(line).length < 3000), isTrue);
    },
  );

  test(
    'failed final event append cannot publish a PASS report on disk',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'qfli-audit-io-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final logs = <String>[];
      final store = await CurriculumAuditStore.create(
        storage: temporary,
        writeLog: logs.add,
      );
      final sessions = _sessions();
      final report = await runCurriculumAudit(
        cases: _cases(),
        platform: 'ohos',
        platformVersion: 'OHOS test',
        sessionFactory: (engine) => sessions[engine]!,
        checkpoint: (current, kind, details) async {
          if (kind == 'AUDIT_COMPLETE') {
            await store.eventFile.delete();
            await Directory(store.eventFile.path).create();
          }
          await store.checkpoint(current, kind, details);
        },
      );
      expect(report.deviceGatePassed, isFalse);
      expect(report.fatalError, contains('checkpoint failed'));
      final saved = jsonDecode(await store.reportFile.readAsString()) as Map;
      expect(saved['deviceGatePassed'], isFalse);
      expect(saved['status'], 'running');
      logs.clear();
      await expectLater(
        store.emitReport(report),
        throwsA(isA<FileSystemException>()),
      );
      final chunks = logs
          .where((line) => line.startsWith('$curriculumAuditMarker DETAIL '))
          .map(
            (line) =>
                jsonDecode(
                      line.substring('$curriculumAuditMarker DETAIL '.length),
                    )
                    as Map,
          )
          .toList();
      final fallback =
          jsonDecode(chunks.map((part) => part['jsonChunk'] as String).join())
              as Map;
      expect(fallback['logOnly'], isTrue);
      expect((fallback['details'] as Map)['deviceGatePassed'], isFalse);
      await Directory(store.eventFile.path).delete();
      await store.emitReport(report);
      final recovered =
          jsonDecode(await store.reportFile.readAsString()) as Map;
      expect(recovered['status'], 'fail');
      expect(recovered['deviceGatePassed'], isFalse);
    },
  );
}
