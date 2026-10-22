import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/android_mysql_runtime.dart';
import 'package:qfli_sql/local_mysql_runtime.dart';
import 'package:qfli_sql/mysql_database.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_native_channel.dart';

import 'sql_curriculum_audit.dart';
import 'sql_curriculum_store.dart';
import 'sql_curriculum_support.dart';

CurriculumEngineSession nativeCurriculumSession(String engine) =>
    switch (engine) {
      'sqlite' => SqliteCurriculumSession(),
      'mysql' => OwnedMySqlCurriculumSession(),
      _ => throw ArgumentError.value(engine, 'engine'),
    };

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class SqliteCurriculumSession implements CurriculumEngineSession {
  final NativeSqliteDatabase _database = const NativeSqliteDatabase();
  bool _timedOut = false;

  @override
  Future<Map<String, Object?>> identify() async {
    final result = await _database.query(
      databasePath: ':memory:',
      source: 'SELECT sqlite_version()',
    );
    _require(
      result.success &&
          !result.truncated &&
          result.rows.length == 1 &&
          result.rows.single.length == 1,
      'Bundled SQLite identity failed: ${result.error}',
    );
    final version = result.rows.single.single;
    _require(
      version != null && version.startsWith('3.50.'),
      'Require the bundled SQLite 3.50 engine, received $version.',
    );
    _require(!_timedOut, 'SQLite identity completed after its deadline.');
    final smoke = await _database.executeScript(
      databasePath: ':memory:',
      source: 'SELECT 1; SELECT 2;',
    );
    _require(
      !_timedOut,
      'SQLite result-set smoke completed after its deadline.',
    );
    _require(
      smoke.success &&
          !smoke.truncated &&
          smoke.results.length == 2 &&
          smoke.results.every(
            (entry) =>
                entry.success &&
                !entry.truncated &&
                entry.rows.length == 1 &&
                entry.rows.single.length == 1,
          ) &&
          smoke.results[0].rows.single.single == '1' &&
          smoke.results[1].rows.single.single == '2',
      'SQLite multi-statement results are not independent dense row sets.',
    );
    final boundarySource =
        '${List.filled(511, 'SELECT 1 WHERE 0;').join()}'
        "SELECT 'limit-kept' AS marker;";
    final atLimit = await _database.executeScript(
      databasePath: ':memory:',
      source: '$boundarySource ; /* trailing trivia */ ; -- final comment',
    );
    _require(!_timedOut, 'SQLite statement-cap smoke exceeded its deadline.');
    _require(
      atLimit.success &&
          !atLimit.truncated &&
          atLimit.results.length == 512 &&
          atLimit.results.last.rows.length == 1 &&
          atLimit.results.last.rows.single.length == 1 &&
          atLimit.results.last.rows.single.single == 'limit-kept',
      'SQLite counted trailing trivia as an extra script statement.',
    );
    final overLimit = await _database.executeScript(
      databasePath: ':memory:',
      source: '${boundarySource}SELECT 513;',
    );
    _require(!_timedOut, 'SQLite statement-cap refusal exceeded its deadline.');
    _require(
      !overLimit.success &&
          overLimit.available &&
          !overLimit.truncated &&
          (overLimit.error?.contains('512 statement limit') ?? false) &&
          overLimit.results.length == 512 &&
          overLimit.results.every((entry) => entry.success) &&
          overLimit.results.last.rows.length == 1 &&
          overLimit.results.last.rows.single.length == 1 &&
          overLimit.results.last.rows.single.single == 'limit-kept',
      'SQLite failed to refuse statement 513 while retaining completed results.',
    );
    return {
      'engine': 'sqlite',
      'version': version,
      'verified': true,
      'platform': Platform.operatingSystem,
      'databasePath': ':memory:',
      'freshConnectionPerScript': true,
      'denseResultSetSmoke': [for (final entry in smoke.results) entry.rows],
      'statementLimitSmoke': {
        'acceptedWithTrailingTrivia': atLimit.results.length,
        'retainedBeforeRefusal': overLimit.results.length,
        'refusal': overLimit.error,
      },
    };
  }

  @override
  Future<SqlScriptResult> execute(CurriculumScript script) {
    _require(
      !_timedOut,
      'SQLite native work timed out; refusing further work.',
    );
    return _database.executeScript(
      databasePath: ':memory:',
      source: script.source,
    );
  }

  @override
  void retainAfterTimeout() => _timedOut = true;

  @override
  Future<Map<String, Object?>> close() async => {
    'success': !_timedOut,
    'persistentUserFilesTouched': false,
    'nativeWorkMayStillBeRunning': _timedOut,
  };
}

/// A new private Oracle root with one independently owned schema per script.
class OwnedMySqlCurriculumSession implements CurriculumEngineSession {
  final String runId =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
  Directory? _project;
  String? _ownedProjectPath;
  Directory? _runtimeRoot;
  String? _ownedRuntimePath;
  NativeMySqlDatabase? _database;
  Future<void> Function()? _stop;
  String? _pidFile;
  bool _timedOut = false;
  bool _runtimeTouched = false;
  bool _closed = false;
  final Set<String> _schemas = {};

  void _active() => _require(
    !_timedOut && !_closed,
    'Owned Oracle runtime is closed or retained after a native timeout.',
  );

  @override
  Future<Map<String, Object?>> identify() async {
    _active();
    _require(
      Platform.isAndroid || Platform.operatingSystem == 'ohos',
      'Oracle curriculum isolation requires an Android/OHOS application.',
    );
    final storage = await curriculumPrivateStorage();
    _active();
    final layout = Platform.isAndroid
        ? await AndroidMySqlRuntime.prepare()
        : null;
    _active();
    if (layout != null) {
      _require(
        p
            .split(layout.dataDirectory.path)
            .contains('com.azurekiln.qfli.sqlab.integrationtest'),
        'Refusing the production Android application sandbox.',
      );
    } else {
      _require(kDebugMode, 'OHOS curriculum isolation requires a debug HAP.');
    }
    final parent = layout != null
        ? layout.temporaryDirectory!.parent
        : await Directory(
            p.join(storage.path, 'curriculum-native'),
          ).create(recursive: true);
    _active();
    // Short private cache root keeps Android Unix socket names below limits.
    _project = await parent.createTemp(layout != null ? 'qc' : '$runId-');
    _ownedProjectPath = await _project!.resolveSymbolicLinks();
    _active();
    if (layout != null) {
      final runtime = LocalMySqlRuntime(
        bundleDirectory: layout.bundleDirectory,
        dataDirectory: Directory(p.join(_project!.path, 'mysql')),
        temporaryDirectory: Directory(p.join(_project!.path, 't')),
        libraryDirectory: layout.libraryDirectory,
        pluginDirectory: layout.pluginDirectory,
        libraryPath: layout.libraryPath,
        launcherPath: layout.launcherPath,
        serverPath: layout.serverPath,
      );
      _runtimeRoot = runtime.dataDirectory;
      _database = NativeMySqlDatabase(runtime: runtime);
      _stop = runtime.stop;
    } else {
      final root = await mysqlNativeChannel.invokeMethod<String>(
        'configureProbeRoot',
        {'runKey': runId},
      );
      _require(
        root != null &&
            p.basename(root) == runId &&
            p.basename(p.dirname(root)) == 'mysql-probe',
        'The OHOS isolated runtime root was not returned.',
      );
      _runtimeRoot = Directory(root!);
      _database = const NativeMySqlDatabase(channel: mysqlNativeChannel);
      _stop = () => mysqlNativeChannel.invokeMethod<void>('stop');
    }
    _active();
    _runtimeTouched = true;
    final result = await _query(
      '',
      'SELECT VERSION(), @@version_comment, @@skip_networking, @@socket, @@pid_file, @@datadir',
    );
    _require(
      result.rows.length == 1 && result.rows.single.length == 6,
      'Oracle identity returned unexpected columns or rows.',
    );
    final row = result.rows.single;
    _require(
      row.every((value) => value != null && value.isNotEmpty),
      'Oracle identity includes missing values.',
    );
    _require(
      row[0] == '8.4.6' && !row[1]!.contains('MariaDB'),
      'Require the pinned real Oracle MySQL 8.4.6, received $row.',
    );
    _require(row[2] == '1', 'Oracle must refuse network listeners.');
    final root = _runtimeRoot!.path;
    _require(
      p.isWithin(_project!.path, row[3]!) || p.isWithin(root, row[3]!),
      'Oracle socket is outside the owned runtime.',
    );
    _require(
      p.isWithin(root, row[4]!) && p.isWithin(root, p.normalize(row[5]!)),
      'Oracle PID/datadir is outside the owned root.',
    );
    _pidFile = row[4];
    _ownedRuntimePath = await _runtimeRoot!.resolveSymbolicLinks();
    _active();
    return {
      'engine': 'mysql',
      'verified': true,
      'version': row[0],
      'versionComment': row[1],
      'skipNetworking': row[2],
      'socket': row[3],
      'pidFile': row[4],
      'dataDirectory': row[5],
      'platform': Platform.operatingSystem,
      'runId': runId,
      'project': _project!.path,
      'runtimeRoot': root,
      'freshSchemaPerScript': true,
    };
  }

  Future<SqlQueryResult> _query(String schema, String source) async {
    _active();
    final result = await _database!.query(databasePath: schema, source: source);
    _active();
    _require(
      result.success && !result.truncated,
      'Oracle query failed or truncated: ${result.error}',
    );
    return result;
  }

  @override
  Future<SqlScriptResult> execute(CurriculumScript script) async {
    _active();
    final schema = 'qfli_curr_${runId}_${script.name}';
    _require(
      schema.length <= 64 && RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(schema),
      'Invalid owned schema name: $schema',
    );
    // Only successful CREATE establishes cleanup ownership; never IF NOT EXISTS.
    await _query('', 'CREATE DATABASE `$schema` CHARACTER SET utf8mb4');
    _schemas.add(schema);
    try {
      return await _database!.executeScript(
        databasePath: schema,
        source: script.source,
      );
    } finally {
      if (!_timedOut) {
        await _query('', 'DROP DATABASE `$schema`');
        _schemas.remove(schema);
      }
    }
  }

  @override
  void retainAfterTimeout() => _timedOut = true;

  Map<String, Object?> _retained() => {
    'success': false,
    'retained': true,
    'runId': runId,
    'reason': 'Native timeout does not cancel SQL; no destructive cleanup.',
    'project': _project?.path,
    'runtimeRoot': _runtimeRoot?.path,
    'schemas': _schemas.toList(),
  };

  @override
  Future<Map<String, Object?>> close() async {
    if (_timedOut) return _retained();
    if (_closed) return {'success': true, 'alreadyClosed': true};
    for (final schema in _schemas.toList()) {
      await _query('', 'DROP DATABASE `$schema`');
      _schemas.remove(schema);
    }
    if (_runtimeTouched) {
      await _stop!();
      if (_timedOut) return _retained();
      _require(
        _pidFile == null || !await File(_pidFile!).exists(),
        'Native stop must finish before deleting owned files.',
      );
    }
    if (_timedOut) return _retained();
    final project = _project;
    if (project != null) {
      final actual = await project.resolveSymbolicLinks();
      _require(
        actual == _ownedProjectPath,
        'Owned project path changed before cleanup.',
      );
      final runtimeRoot = _runtimeRoot;
      if (runtimeRoot != null && await runtimeRoot.exists()) {
        final root = await runtimeRoot.resolveSymbolicLinks();
        _require(
          _ownedRuntimePath == null || root == _ownedRuntimePath,
          'Owned runtime path changed before cleanup.',
        );
        if (!p.isWithin(actual, root)) {
          _require(
            p.basename(p.dirname(root)) == 'mysql-probe' &&
                p.basename(root) == runId,
            'Refusing cleanup outside the uniquely owned Oracle probe root.',
          );
          if (_timedOut) return _retained();
          await Directory(root).delete(recursive: true);
        }
      }
      if (_timedOut) return _retained();
      await Directory(actual).delete(recursive: true);
    }
    _closed = true;
    return {
      'success': true,
      'runId': runId,
      'schemasRemoved': true,
      'runtimeStopped': !_runtimeTouched || _stop != null,
      'projectRemoved': true,
    };
  }
}
