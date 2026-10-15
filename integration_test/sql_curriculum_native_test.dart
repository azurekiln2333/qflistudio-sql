import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/android_mysql_runtime.dart';
import 'package:qfli_sql/local_mysql_runtime.dart';
import 'package:qfli_sql/mysql_database.dart';
import 'package:qfli_sql/sql_content_repository.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_native_channel.dart';
import 'package:qfli_studio_core/services/app_paths.dart';

const _marker = 'QFLI_SQL_CURRICULUM_NATIVE';
const _mysqlLessons = [121, 122, 123, 124, 125, 126];
const _deadline = Duration(minutes: 4);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<_OwnedRuntime>? runtime;
  final catalog = SqlContentRepository(bundle: rootBundle);

  tearDownAll(() async {
    final pending = runtime;
    if (pending != null) await (await pending).close();
  });

  for (final number in _mysqlLessons) {
    testWidgets(
      'bundled MySQL lesson $number and its authored exercise outputs',
      (tester) async {
        final content = await catalog.load();
        final mysqlExamples = content.examples.where(
          (example) => example.inputFixtures['engine'] == 'mysql',
        );
        expect(
          mysqlExamples.map((example) => example.id).toSet(),
          _mysqlLessons.map((id) => 'sql-example-$id').toSet(),
          reason: 'Every shipped MySQL-only lesson must be exercised.',
        );
        final example = mysqlExamples.singleWhere(
          (example) => example.id == 'sql-example-$number',
        );
        final lesson = content.tutorials
            .expand((tutorial) => tutorial.lessons)
            .singleWhere((lesson) => lesson.id == example.sourceLessonId);
        expect(example.code, lesson.code, reason: '${example.id} code drift');
        expect(example.expectedOutput, lesson.output);
        final setup = example.inputFixtures['exerciseSetup'];
        expect(
          setup,
          isNotNull,
          reason: '${example.id} missing exercise setup',
        );
        final expected = jsonDecode(
          example.inputFixtures['exerciseExpectedOutputs'] ?? 'null',
        );
        expect(expected, isA<List>());
        final outputs = List<String>.from(expected as List);
        expect(outputs, hasLength(lesson.exercises.length));
        expect(outputs, isNotEmpty);
        expect(
          outputs.every((output) => output.trim().isNotEmpty),
          isTrue,
          reason: 'Empty results must explicitly use (no rows).',
        );

        final native = await (runtime ??= _OwnedRuntime.open());
        await native.verify(
          'lesson_$number',
          example.code,
          example.expectedOutput,
        );
        for (var index = 0; index < lesson.exercises.length; index++) {
          // Each exercise starts from the authored setup in a new schema,
          // without inheriting mutations made by the lesson's final query.
          await native.verify(
            'exercise_${number}_$index',
            '${setup!.trimRight()}\n${lesson.exercises[index].answer}',
            outputs[index],
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}

/// Uses bundled native binaries with a newly owned runtime root. No default
/// datadir, engine preference, production project or account is modified.
class _OwnedRuntime {
  _OwnedRuntime({
    required this.runId,
    required this.project,
    required this.runtimeRoot,
    required this.database,
    required this.stop,
  });

  final String runId;
  final Directory project;
  final Directory runtimeRoot;
  final NativeMySqlDatabase database;
  final Future<void> Function() stop;
  final Set<String> _schemas = {};
  bool _timedOut = false;
  String? _pidFile;

  static Future<_OwnedRuntime> open() async {
    if (!Platform.isAndroid && Platform.operatingSystem != 'ohos') {
      throw UnsupportedError('This target requires a real Android/OHOS app.');
    }
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final runId =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$random';
    final storage = await AppPaths.storageDirectory();
    if (storage == null) {
      throw StateError('App-private storage is unavailable.');
    }
    final parent = await Directory(
      p.join(storage, 'curriculum-native'),
    ).create(recursive: true);
    final project = await parent.createTemp('$runId-');
    late _OwnedRuntime owned;
    if (Platform.isAndroid) {
      final layout = await AndroidMySqlRuntime.prepare();
      if (!p
          .split(layout.dataDirectory.path)
          .contains('com.azurekiln.qfli.sqlab.integrationtest')) {
        throw StateError(
          'Refusing the production Android application sandbox.',
        );
      }
      final runtime = LocalMySqlRuntime(
        bundleDirectory: layout.bundleDirectory,
        dataDirectory: Directory(p.join(project.path, 'mysql')),
        temporaryDirectory: Directory(p.join(project.path, 'tmp')),
        libraryDirectory: layout.libraryDirectory,
        pluginDirectory: layout.pluginDirectory,
        libraryPath: layout.libraryPath,
        launcherPath: layout.launcherPath,
        serverPath: layout.serverPath,
      );
      owned = _OwnedRuntime(
        runId: runId,
        project: project,
        runtimeRoot: runtime.dataDirectory,
        database: NativeMySqlDatabase(runtime: runtime),
        stop: runtime.stop,
      );
    } else {
      if (!kDebugMode) {
        throw StateError('OHOS curriculum isolation requires a debug HAP.');
      }
      // The native method rejects existing roots and refuses a second
      // reconfiguration. It cannot adopt or overwrite production MySQL data.
      final root = await mysqlNativeChannel
          .invokeMethod<String>('configureProbeRoot', {'runKey': runId})
          .timeout(_deadline);
      if (root == null ||
          p.basename(root) != runId ||
          p.basename(p.dirname(root)) != 'mysql-probe') {
        throw StateError('The OHOS isolated runtime root was not returned.');
      }
      owned = _OwnedRuntime(
        runId: runId,
        project: project,
        runtimeRoot: Directory(root),
        database: const NativeMySqlDatabase(channel: mysqlNativeChannel),
        stop: () => mysqlNativeChannel.invokeMethod<void>('stop'),
      );
    }
    try {
      final identity = await owned._query(
        '',
        'SELECT VERSION(), @@version_comment, @@skip_networking, @@socket, @@pid_file',
      );
      expect(identity.rows, hasLength(1));
      final row = identity.rows.single;
      expect(row[0], '8.4.6', reason: 'Require the pinned real Oracle engine.');
      expect(row[1], isNot(contains('MariaDB')));
      expect(row[2], '1', reason: 'The runtime must use its private socket.');
      expect(
        p.isWithin(project.path, row[3]!) ||
            p.isWithin(owned.runtimeRoot.path, row[3]!),
        isTrue,
      );
      expect(p.isWithin(owned.runtimeRoot.path, row[4]!), isTrue);
      owned._pidFile = row[4];
      _log('IDENTITY', {
        'runId': runId,
        'version': row[0],
        'comment': row[1],
        'skipNetworking': row[2],
        'socket': row[3],
        'pidFile': row[4],
        'project': project.path,
        'runtimeRoot': owned.runtimeRoot.path,
      });
      return owned;
    } on Object {
      await owned.close();
      rethrow;
    }
  }

  Future<SqlQueryResult> _query(String schema, String source) async {
    try {
      final result = await database
          .query(databasePath: schema, source: source)
          .timeout(_deadline);
      expect(result.available, isTrue, reason: result.error);
      expect(result.success, isTrue, reason: result.error);
      expect(result.truncated, isFalse);
      return result;
    } on TimeoutException {
      _timedOut = true;
      rethrow;
    }
  }

  Future<void> verify(String name, String source, String expected) async {
    if (_timedOut) {
      throw StateError('Native SQL timed out; refusing further work.');
    }
    final schema = 'qfli_curr_${runId}_$name';
    // No IF NOT EXISTS: only a successful CREATE establishes cleanup ownership.
    await _query('', 'CREATE DATABASE `$schema` CHARACTER SET utf8mb4');
    _schemas.add(schema);
    try {
      final script = await database
          .executeScript(databasePath: schema, source: source)
          .timeout(_deadline);
      expect(script.available, isTrue, reason: '$name: ${script.error}');
      expect(script.success, isTrue, reason: '$name: ${script.error}');
      expect(script.truncated, isFalse, reason: name);
      expect(script.results, isNotEmpty, reason: name);
      for (final result in script.results) {
        expect(result.success, isTrue, reason: '$name: ${result.error}');
        expect(result.truncated, isFalse, reason: name);
      }
      final queryResults = script.results.where(
        (result) => result.columns.isNotEmpty,
      );
      expect(
        queryResults,
        isNotEmpty,
        reason: '$name must produce a query result, even if it has zero rows.',
      );
      final actual = queryResults
          .expand((result) => result.rows)
          .map((row) => row.map((value) => value ?? '').join('|'))
          .join('\n');
      final target = expected.trim() == '(no rows)' ? '' : _normalize(expected);
      expect(_normalize(actual), target, reason: '$name authored result');
      _log('PASS', {
        'runId': runId,
        'name': name,
        'schema': schema,
        'expected': target,
        'actual': _normalize(actual),
      });
    } on TimeoutException {
      _timedOut = true;
      rethrow;
    } finally {
      if (!_timedOut) {
        await _query('', 'DROP DATABASE `$schema`');
        _schemas.remove(schema);
      }
    }
  }

  Future<void> close() async {
    if (_timedOut) {
      _log('RETAINED', {
        'runId': runId,
        'reason': 'native timeout',
        'project': project.path,
        'runtimeRoot': runtimeRoot.path,
      });
      // A Dart timeout does not cancel native SQL. Never delete an active root.
      return;
    }
    for (final schema in _schemas.toList()) {
      await _query('', 'DROP DATABASE `$schema`');
      _schemas.remove(schema);
    }
    await stop().timeout(_deadline);
    if (_pidFile != null) {
      expect(
        await File(_pidFile!).exists(),
        isFalse,
        reason: 'Native stop must finish before deleting an owned fixture.',
      );
    }
    final actual = await project.resolveSymbolicLinks();
    expect(p.basename(p.dirname(actual)), 'curriculum-native');
    expect(p.basename(actual).startsWith('$runId-'), isTrue);
    final root = runtimeRoot.path;
    if (!p.isWithin(actual, root)) {
      expect(p.basename(p.dirname(root)), 'mysql-probe');
      expect(p.basename(root), runId);
      if (await runtimeRoot.exists()) await runtimeRoot.delete(recursive: true);
    }
    await Directory(actual).delete(recursive: true);
    _log('CLEANUP', {
      'runId': runId,
      'schemas': 'removed',
      'runtimeStopped': true,
    });
  }
}

String _normalize(String text) => text
    .trim()
    .split('\n')
    .map((line) => line.trimRight())
    .where((line) => line.isNotEmpty)
    .join('\n');

void _log(String kind, Map<String, Object?> details) =>
    debugPrintSynchronously('$_marker $kind ${jsonEncode(details)}');
