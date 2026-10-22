import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

import '../integration_test/support/sql_curriculum_audit.dart';
import '../integration_test/support/sql_curriculum_store.dart';
import '../integration_test/support/sql_curriculum_support.dart';

/// Tests the actual Dart store -> Python collector boundary. The execution
/// sessions below are explicit protocol fixtures, never device/engine evidence.
void main() {
  test(
    'actual Dart reports and Unicode log chunks survive strict offline collection',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'qfli-collector-fixture-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final examples = <Map<String, Object?>>[];
      final tutorials = <Map<String, Object?>>[];
      for (final (index, engine) in [(1, 'sqlite'), (2, 'mysql')]) {
        final code = "SELECT 1; -- ${List.filled(200, '鸿蒙🌏').join()} $engine";
        final lessonId = 'transport-lesson-$index';
        tutorials.add({
          'id': 'transport-tutorial-$index',
          'type': 'sql',
          'language': 'sql',
          'title': 'Protocol fixture $index',
          'lessons': [
            {
              'id': lessonId,
              'title': 'Protocol fixture $index',
              'code': code,
              'output': '1',
              'exercises': [
                for (var exercise = 0; exercise < 2; exercise++)
                  {'prompt': 'Fixture', 'answer': 'SELECT 1;'},
              ],
            },
          ],
        });
        examples.add({
          'id': 'transport-example-$index',
          'type': 'sql',
          'language': 'sql',
          'title': 'Protocol fixture $index',
          'code': code,
          'expectedOutput': '1',
          'sourceLessonId': lessonId,
          'inputFixtures': {
            'engine': engine,
            'exerciseSetup': '-- transport fixture only',
            'exerciseExpectedOutputs': '["1", "1"]',
          },
        });
      }
      final exampleSource = jsonEncode({'entries': examples});
      final tutorialSource = jsonEncode({'entries': tutorials});
      final exampleFile = File(p.join(temporary.path, 'examples.json'))
        ..writeAsStringSync(exampleSource);
      final tutorialFile = File(p.join(temporary.path, 'tutorials.json'))
        ..writeAsStringSync(tutorialSource);
      final catalog = ContentCatalog.fromJson(
        examplesSource: exampleSource,
        tutorialsSource: tutorialSource,
      );
      final lines = <String>[];
      final store = await CurriculumAuditStore.create(
        storage: temporary,
        metadata: {
          'buildId': 'dart-transport-fixture',
          'requestedEngines': 'sqlite,mysql',
        },
        writeLog: lines.add,
      );
      final report = await runCurriculumAudit(
        cases: curriculumCases(catalog),
        platform: 'ohos',
        platformVersion: 'PROTOCOL FIXTURE, not a device',
        sessionFactory: _FixtureSession.new,
        checkpoint: store.checkpoint,
      );
      await store.emitReport(report);
      final saved = jsonDecode(await store.reportFile.readAsString()) as Map;
      final logFile = File(p.join(temporary.path, 'hilog.txt'));
      await logFile.writeAsString(
        lines.map((line) => '10-22 20:00:00.000 I/flutter: $line').join('\n'),
      );

      Future<ProcessResult> collect(String destination, List<String> input) =>
          Process.run(
            Platform.environment['PYTHON'] ?? 'python',
            [
              'tool/ohos/collect_curriculum_audit.py',
              ...input,
              '--run-id',
              store.runId,
              '--expected-build-id',
              'dart-transport-fixture',
              '--expected-platform',
              'ohos',
              '--catalog-examples',
              exampleFile.path,
              '--catalog-tutorials',
              tutorialFile.path,
              '--expected-examples',
              '2',
              '--expected-scripts',
              '6',
              '--output-dir',
              p.join(temporary.path, destination),
            ],
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );

      final fromLog = await collect('from-log', ['--hilog', logFile.path]);
      expect(
        fromLog.exitCode,
        0,
        reason: '${fromLog.stdout}\n${fromLog.stderr}',
      );
      final fromFiles = await collect('from-files', [
        '--report',
        store.reportFile.path,
        '--events',
        store.eventFile.path,
      ]);
      expect(
        fromFiles.exitCode,
        0,
        reason: '${fromFiles.stdout}\n${fromFiles.stderr}',
      );
      for (final name in ['from-log', 'from-files']) {
        final recovered = jsonDecode(
          await File(
            p.join(temporary.path, name, 'report.json'),
          ).readAsString(),
        );
        expect(recovered, saved);
        final summary =
            jsonDecode(
                  await File(
                    p.join(temporary.path, name, 'summary.json'),
                  ).readAsString(),
                )
                as Map;
        expect(summary['collectionValidated'], isTrue);
        expect(summary['catalogScripts'], 6);
        expect(summary['deviceGatePassed'], isTrue);
      }
      final missing = lines.lastIndexWhere(
        (line) =>
            line.startsWith('$curriculumAuditMarker DETAIL ') &&
            line.contains('"kind":"REPORT"'),
      );
      expect(missing, greaterThanOrEqualTo(0));
      final broken = [...lines]..removeAt(missing);
      await logFile.writeAsString(broken.join('\n'));
      final incomplete = await collect('missing-chunk', [
        '--hilog',
        logFile.path,
      ]);
      expect(incomplete.exitCode, 2);
      final summary = jsonDecode(incomplete.stdout as String) as Map;
      expect(summary['collectionValidated'], isFalse);
      expect(summary['deviceGatePassed'], isFalse);
      expect(
        summary['validationErrors'].toString(),
        contains('Missing REPORT chunks'),
      );
    },
  );
}

class _FixtureSession implements CurriculumEngineSession {
  _FixtureSession(this.engine);
  final String engine;

  @override
  Future<Map<String, Object?>> identify() async => {
    'engine': engine,
    'platform': 'ohos',
    'version': 'fixture',
    'verified': true,
  };

  @override
  Future<SqlScriptResult> execute(CurriculumScript script) async {
    const query = SqlQueryResult(
      available: true,
      exitCode: 0,
      columns: ['value'],
      rows: [
        ['1'],
      ],
      affectedRows: 0,
      truncated: false,
    );
    return const SqlScriptResult(summary: query, results: [query]);
  }

  @override
  void retainAfterTimeout() {}

  @override
  Future<Map<String, Object?>> close() async => {'success': true};
}
