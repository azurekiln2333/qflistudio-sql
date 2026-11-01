import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/mysql_database.dart';
import 'package:qfli_sql/mysql_workspace_repository.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_native_channel.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_runner.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/services/app_paths.dart';

// A manually installed HAP entrypoint: no integration-test binding, mock
// messenger, plugin replacement, preference writes, or automatic uninstall.
const _marker = 'QFLI_MYSQL_OHOS_PROBE';
const _readOnly = bool.fromEnvironment('QFLI_MYSQL_PROBE_READ_ONLY');
const _largeId = '9007199254740993';
const _decimal = '12345678901234.123456';
const _unicode = "你好，鸿蒙 🌏 O'Brien;value";
const _updated = 'persisted: $_unicode';
const _savedSource = 'SELECT value FROM probe_editor ORDER BY id;';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final _lines = <String>[];
  String _status = _readOnly ? 'Reading saved report' : 'Running phone probe';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    try {
      final probe = _PhoneProbe((line) {
        if (mounted) setState(() => _lines.add(line));
      });
      final status = await probe.run();
      if (mounted) setState(() => _status = status);
    } on Object catch (error, stack) {
      final line =
          '$_marker FAIL ${jsonEncode({'error': error.toString(), 'stackTrace': stack.toString()})}';
      debugPrintSynchronously(line);
      if (mounted) {
        setState(() {
          _lines.add(line);
          _status = 'FAIL · probe setup';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(title: const Text('Oracle MySQL · OHOS probe')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status, style: const TextStyle(fontSize: 20)),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: SelectableText(
                  _lines.join('\n\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Deadlines wrap the real production adapter, including calls made by the
// repository/editor. A timeout aborts the Dart caller; it never substitutes
// results or continues to the next SQL mutation. Native cancellation is not
// implied, so failed runs retain their owned fixture for diagnosis.
class _OhosDatabase extends NativeMySqlDatabase {
  const _OhosDatabase() : super(channel: mysqlNativeChannel);

  static const _deadline = Duration(minutes: 4);

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) => super
      .query(databasePath: databasePath, source: source, parameters: parameters)
      .timeout(_deadline);

  @override
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
  }) => super
      .executeScript(databasePath: databasePath, source: source)
      .timeout(_deadline);
}

class _ProbeFailure implements Exception {
  const _ProbeFailure(this.message, [this.evidence]);

  final String message;
  final Object? evidence;

  @override
  String toString() => message;
}

class _PhoneProbe {
  _PhoneProbe(this.onLine);

  final void Function(String) onLine;
  final String runId = _newRunId();
  final _clock = Stopwatch()..start();
  final _checks = <Map<String, Object?>>[];
  final _report = <String, Object?>{};
  final _cleanup = <String, Object?>{
    'schemaDropped': false,
    'projectRemoved': false,
    'runtimeStopped': false,
  };
  NativeMySqlDatabase _database = const _OhosDatabase();
  Directory? _reportRoot;
  Directory? _runDirectory;
  Directory? _project;
  File? _reportFile;
  bool _ownsSchema = false;
  bool _runtimeTouched = false;
  String? _pidFile;
  String? _socket;
  String? _serverUuid;
  int? _serverPid;

  String get schema => 'qfli_project_ohosprobe_$runId';

  static String _newRunId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  Future<String> run() async {
    if (_readOnly) return _replay();
    _report.addAll({
      'formatVersion': 1,
      'probe': _marker,
      'runId': runId,
      'status': 'running',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'flutterPid': pid,
      'schema': schema,
      'checks': _checks,
      'cleanup': _cleanup,
    });
    _log('START', {'platform': Platform.operatingSystem, 'schema': schema});
    Object? failure;
    try {
      _require(
        Platform.operatingSystem == 'ohos',
        'An OHOS device is required.',
      );
      final storage = await AppPaths.storageDirectory();
      _require(storage != null, 'App-private storage is unavailable.');
      _reportRoot = await Directory(
        p.join(storage!, 'mysql-ohos-probe'),
      ).create(recursive: true);
      _runDirectory = await _reportRoot!.createTemp('$runId-');
      _reportFile = File(p.join(_runDirectory!.path, 'report.json'));
      _report['reportPath'] = _reportFile!.path;
      _log('REPORT', {'path': _reportFile!.path});
      await _saveReport();

      // Isolate the Oracle runtime from production data: point it at a unique
      // probe-only root BEFORE any server/init is owned, and record the actual
      // native root for PID/log evidence.
      const channel = MethodChannel('qfli_sql/mysql');
      final probeRoot = await channel.invokeMethod<String>(
        'configureProbeRoot',
        <String, Object?>{'runKey': runId},
      );
      _require(probeRoot != null && probeRoot.isNotEmpty,
        'The Oracle probe runtime root was not returned.');
      _report['runtimeRoot'] = probeRoot;
      _log('RUNTIME_ROOT', {'root': probeRoot});

      // Option-B prototype instrumentation (debug-only): load the private,
      // statically linked Oracle prototype DSO with RTLD_LOCAL, read the real
      // constructor-time thread/atfork counters, and verify child-local exit
      // interception. This is measurement only; the production host is not used.
      final proto = await channel.invokeMethod<Map<Object?, Object?>>('protoProbe');
      final protoEvidence = <String, Object?>{
        'loaded': proto?['loaded'],
        'ready': proto?['ready'],
        'threadCalls': proto?['threadCalls'],
        'atforkCalls': proto?['atforkCalls'],
        'exitIntercepts': proto?['exitIntercepts'],
        'childExitIsolated': proto?['childExitIsolated'],
        'childPid': proto?['childPid'],
        'owned': proto?['owned'],
        'pendingPid': proto?['pendingPid'],
        'error': proto?['error'],
      };
      _report['protoInstrumentation'] = protoEvidence;
      _log('PROTO_INSTRUMENTATION', protoEvidence);
      // Real quiescence gate: all conditions must actually hold, otherwise this
      // check fails rather than reporting a bare returned map as PASS.
      await _check('proto_closure_quiescent', () async {
        _require(proto != null, 'protoProbe returned no result.', protoEvidence);
        _require(protoEvidence['loaded'] == true, 'prototype DSO not loaded.', protoEvidence);
        _require(protoEvidence['ready'] == true, 'prototype binding not ready.', protoEvidence);
        _require(protoEvidence['threadCalls'] == 0,
          'constructor-time thread creation observed.', protoEvidence);
        _require(protoEvidence['atforkCalls'] == 0,
          'constructor-time atfork registration observed.', protoEvidence);
        _require(protoEvidence['childExitIsolated'] == true,
          'child-local exit interception was not verified.', protoEvidence);
        return protoEvidence;
      });
      await _check('oracle_identity_and_socket', () => _inspectServer());
      await _check('create_owned_schema', () async {
        // No IF NOT EXISTS: a collision fails without claiming ownership.
        final result = await _database.query(
          databasePath: '',
          source:
              'CREATE DATABASE `$schema` '
              'CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci',
        );
        _ownsSchema = result.success;
        _requireResult(result);
        _project = await _runDirectory!.createTemp('project-');
        _report['projectPath'] = _project!.path;
        return {'schema': schema, 'projectPath': _project!.path};
      });
      await _check('crud_exact_values', _crud);
      await _check('invalid_sql_is_available', _invalidSql);
      await _check('scripts_transactions_and_literals', _scripts);
      await _check('workbench_repository_round_trip', _workbench);
      await _check('project_editor_and_saved_query', _editor);
      await _check('stop_runtime', _stop);
      await _check('restart_persistence', _restart);
      await _check('cleanup_owned_fixture', _removeFixture);
    } on Object catch (error, stack) {
      failure = error;
      _report['error'] = error.toString();
      _report['stackTrace'] = stack.toString();
      if (error is _ProbeFailure) _report['errorEvidence'] = error.evidence;
    } finally {
      if (_runtimeTouched) {
        try {
          await _check('final_stop', _stop, checkpointBefore: false);
        } on Object catch (error, stack) {
          failure ??= error;
          _report['shutdownError'] = error.toString();
          _report['shutdownStackTrace'] = stack.toString();
        }
      }
    }

    _cleanup['schemaRetained'] = _ownsSchema;
    _cleanup['projectRetained'] = _project != null;
    _report['status'] = failure == null ? 'pass' : 'fail';
    _report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    _report['elapsedMs'] = _clock.elapsedMilliseconds;
    try {
      await _saveReport();
    } on Object catch (error) {
      failure ??= error;
      _report['status'] = 'fail';
      _report['reportWriteError'] = error.toString();
      _log('REPORT_ERROR', {'error': error.toString()});
    }
    final status = failure == null ? 'PASS' : 'FAIL';
    _log(status, {
      'status': status.toLowerCase(),
      'reportPath': _reportFile?.path,
      'server': _report['server'],
      'checksPassed': _checks
          .where((check) => check['status'] == 'pass')
          .length,
      'cleanup': _cleanup,
      if (failure != null) 'error': failure.toString(),
      if (_report['errorEvidence'] != null)
        'errorEvidence': _report['errorEvidence'],
    });
    return '$status · ${_reportFile?.path ?? 'See console diagnostics'}';
  }

  Future<Map<String, Object?>> _inspectServer({bool restarted = false}) async {
    _runtimeTouched = true;
    _cleanup['runtimeStopped'] = false;
    final result = await _query(
      'SELECT VERSION(), @@version_comment, @@skip_networking, @@port, '
      '@@socket, @@pid_file, @@server_uuid',
      databaseName: '',
    );
    _require(
      result.rows.length == 1 && result.rows.single.length == 7,
      'Server identity query returned an unexpected shape.',
      _evidence(result),
    );
    final row = result.rows.single;
    // The server's socket, pid file and datadir must live under the probe root
    // returned by the runtime, proving the isolated root was actually used.
    final probeRoot = _report['runtimeRoot'] as String?;
    for (final entry in <String, Object?>{'socket': row[4], 'pidFile': row[5]}.entries) {
      final value = entry.value?.toString() ?? '';
      _require(
        probeRoot != null && probeRoot.isNotEmpty && value.startsWith(probeRoot),
        'Oracle ${entry.key} is not under the isolated probe root.',
        {'probeRoot': probeRoot, 'value': value},
      );
    }
    final identity = <String, Object?>{
      'version': row[0],
      'versionComment': row[1],
      'skipNetworking': row[2],
      'port': row[3],
      'socket': row[4],
      'pidFile': row[5],
      'serverUuid': row[6],
    };
    _report[restarted ? 'restartedServer' : 'server'] = identity;
    _require(row[0] == '8.4.6', 'Expected Oracle MySQL 8.4.6.', identity);
    _require(
      !'${row[0]} ${row[1]}'.toLowerCase().contains('mariadb'),
      'MariaDB does not satisfy Oracle acceptance.',
      identity,
    );
    _require(row[2] == '1', 'MySQL TCP networking must be disabled.', identity);
    final socket = row[4];
    final pidFile = row[5];
    _require(
      socket != null && p.isAbsolute(socket),
      'MySQL must expose an absolute Unix socket path.',
      identity,
    );
    _require(
      pidFile != null && p.isAbsolute(pidFile),
      'MySQL must report its app-private PID file.',
      identity,
    );
    _require(
      p.dirname(socket!) == p.dirname(pidFile!),
      'Socket and PID file must belong to the same private runtime.',
      identity,
    );
    final serverPid = int.tryParse((await File(pidFile).readAsString()).trim());
    _require(
      serverPid != null && serverPid > 1 && serverPid != pid,
      'Oracle must run in a separate server process.',
      identity,
    );
    identity['serverPid'] = serverPid;
    _require(
      row[6] != null && row[6]!.isNotEmpty,
      'MySQL did not return its persistent server UUID.',
      identity,
    );
    if (restarted) {
      _require(
        serverPid != _serverPid,
        'Stop/restart reused the server process.',
        {'beforePid': _serverPid, 'after': identity},
      );
      _require(
        row[6] == _serverUuid && socket == _socket && pidFile == _pidFile,
        'Restart must reuse the original datadir and private socket.',
        identity,
      );
    }
    _serverPid = serverPid;
    _serverUuid = row[6];
    _socket = socket;
    _pidFile = pidFile;
    return identity;
  }

  Future<Map<String, Object?>> _crud() async {
    await _query(
      'CREATE TABLE probe_values ('
      'id BIGINT PRIMARY KEY, message TEXT NOT NULL, note TEXT NULL, '
      'payload BLOB NULL, amount DECIMAL(20,6) NOT NULL) ENGINE=InnoDB',
    );
    const insert =
        'INSERT INTO probe_values '
        '(id,message,note,payload,amount) VALUES (?,?,?,UNHEX(?),?)';
    for (final values in <List<String?>>[
      [_largeId, _unicode, null, '00FF0080', _decimal],
      ['2', 'empty', '', '', '0'],
      ['3', 'sql-null', null, null, '0'],
    ]) {
      final inserted = await _query(insert, parameters: values);
      _require(inserted.affectedRows == 1, 'INSERT must affect one row.');
    }
    final initial = await _query(
      'SELECT id,message,note,payload,amount FROM probe_values ORDER BY id',
    );
    _rows(initial, [
      ['2', 'empty', '', '', '0.000000'],
      ['3', 'sql-null', null, null, '0.000000'],
      [_largeId, _unicode, null, '00FF0080', _decimal],
    ]);
    _require(
      initial.columnInfo.length == 5 && initial.columnInfo[3].binary,
      'Native BLOB metadata is missing.',
      _evidence(initial),
    );
    // Repeating an unchanged update also verifies CLIENT_FOUND_ROWS.
    for (var attempt = 0; attempt < 2; attempt++) {
      final updated = await _query(
        'UPDATE probe_values SET message=? WHERE id=?',
        parameters: [_updated, _largeId],
      );
      _require(
        updated.affectedRows == 1,
        'UPDATE must report one matched row.',
      );
    }
    final deleted = await _query(
      'DELETE FROM probe_values WHERE id=?',
      parameters: ['2'],
    );
    _require(deleted.affectedRows == 1, 'DELETE must affect one row.');
    final values = await _readValues();
    return {'initialRows': initial.rows, 'persistedRows': values.rows};
  }

  Future<SqlQueryResult> _readValues() async {
    final result = await _query(
      'SELECT id,message,note,payload,amount FROM probe_values ORDER BY id',
    );
    _rows(result, [
      ['3', 'sql-null', null, null, '0.000000'],
      [_largeId, _updated, null, '00FF0080', _decimal],
    ]);
    return result;
  }

  Future<Map<String, Object?>> _invalidSql() async {
    final invalid = await _database.query(
      databasePath: schema,
      source: 'SELEC deliberately_invalid_sql',
    );
    _require(
      invalid.available &&
          !invalid.success &&
          invalid.exitCode == 1064 &&
          invalid.sqlState == '42000' &&
          (invalid.error?.isNotEmpty ?? false),
      'SQL syntax errors must preserve availability and Oracle diagnostics.',
      _evidence(invalid),
    );
    _rows(await _query('SELECT 1'), [
      ['1'],
    ]);
    return _evidence(invalid);
  }

  Future<Map<String, Object?>> _scripts() async {
    await _query(
      'CREATE TABLE probe_transactions '
      '(id INTEGER PRIMARY KEY, value TEXT NOT NULL) ENGINE=InnoDB',
    );
    final rolledBack = await _database.executeScript(
      databasePath: '',
      source:
          'USE `$schema`; START TRANSACTION; '
          "INSERT INTO probe_transactions VALUES (1,'rolled;back'); ROLLBACK; "
          'SELECT COUNT(*) FROM probe_transactions; /* comment; not SQL */ '
          "SELECT 'semi;colon', 'O''Brien';",
    );
    _requireScript(rolledBack);
    _require(
      rolledBack.results.length == 6,
      'USE and transaction statements must preserve ordered script results.',
    );
    _require(
      rolledBack.results[2].affectedRows == 1,
      'The rolled-back INSERT did not execute.',
    );
    _rows(rolledBack.results[4], [
      ['0'],
    ]);
    _rows(rolledBack.results[5], [
      ['semi;colon', "O'Brien"],
    ]);
    final committed = await _database.executeScript(
      databasePath: schema,
      source:
          'START TRANSACTION; '
          "INSERT INTO probe_transactions VALUES (2,'committed;鸿蒙'); COMMIT; "
          'SELECT id,value FROM probe_transactions ORDER BY id;',
    );
    _requireScript(committed);
    _rows(committed.results.last, [
      ['2', 'committed;鸿蒙'],
    ]);
    final partial = await _database.executeScript(
      databasePath: schema,
      source:
          "INSERT INTO probe_transactions VALUES (3,'before-error'); "
          'SELECT missing_column FROM probe_transactions; '
          "INSERT INTO probe_transactions VALUES (4,'must-not-run');",
    );
    _require(
      partial.available &&
          !partial.success &&
          partial.exitCode == 1054 &&
          partial.results.isNotEmpty &&
          partial.results.first.affectedRows == 1,
      'A partial script failure must report the committed prefix and error.',
      _evidence(partial.summary),
    );
    final persisted = await _readTransactions();
    return {
      'rollbackCount': rolledBack.results[4].rows,
      'literals': rolledBack.results[5].rows,
      'committedRows': persisted.rows,
      'partialError': _evidence(partial.summary),
    };
  }

  Future<SqlQueryResult> _readTransactions() async {
    final result = await _query(
      'SELECT id,value FROM probe_transactions ORDER BY id',
    );
    _rows(result, [
      ['2', 'committed;鸿蒙'],
      ['3', 'before-error'],
    ]);
    return result;
  }

  MySqlWorkspaceRepository get _workspace => MySqlWorkspaceRepository(
    runtimeDirectory: _project!,
    database: _database,
  );

  Future<Map<String, Object?>> _workbench() async {
    final workspace = _workspace;
    _require(
      (await workspace.listDatabases()).contains(schema),
      'The owned schema is missing from the database explorer.',
    );
    await workspace.createTable(schema, 'probe_grid', const [
      SqlColumnDraft(name: 'id', type: 'BIGINT', primaryKey: true),
      SqlColumnDraft(name: 'note', type: 'TEXT'),
      SqlColumnDraft(name: 'payload', type: 'BLOB'),
    ]);
    await workspace.insertRow(schema, 'probe_grid', {
      'id': _largeId,
      'note': null,
      'payload': '00FF',
    });
    var page = await workspace.loadTable(schema, 'probe_grid');
    _require(
      page.editable && page.totalRows == 1 && page.rowIds.length == 1,
      'The actual primary-key row must be editable.',
    );
    _sameRows(page.rows, [
      [_largeId, null, '00FF'],
    ]);
    await workspace.updateCell(
      schema,
      'probe_grid',
      page.rowIds.single,
      'note',
      'grid;鸿蒙',
    );
    await workspace.updateCell(
      schema,
      'probe_grid',
      page.rowIds.single,
      'payload',
      '80FF00',
    );
    await workspace.insertRow(schema, 'probe_grid', {
      'id': '1',
      'note': 'delete only this row',
      'payload': '',
    });
    page = await workspace.loadTable(schema, 'probe_grid');
    _require(page.rows.first.first == '1', 'Grid ordering lost the exact key.');
    await workspace.deleteRow(schema, 'probe_grid', page.rowIds.first);
    page = await workspace.loadTable(schema, 'probe_grid');
    _sameRows(page.rows, [
      [_largeId, 'grid;鸿蒙', '80FF00'],
    ]);
    _require(
      (await workspace.listTables(schema)).contains('probe_grid'),
      'The owned table is missing from the explorer.',
    );
    return {'rows': page.rows, 'editable': page.editable};
  }

  Future<Map<String, Object?>> _editor() async {
    // Seed only this new test project's marker with the already owned schema.
    // The production engine exercises its marker/script handling without
    // creating another schema or changing the user's engine preference.
    final marker = File(p.join(_project!.path, '.qfli', 'mysql.json'));
    await marker.parent.create(recursive: true);
    await marker.writeAsString(jsonEncode({'schema': schema}), flush: true);
    final engine = NativeMySqlEngine(database: _database);
    final written = await engine.execute(
      SqlProgramRequest(
        projectPath: _project!.path,
        source:
            'CREATE TABLE probe_editor (id INTEGER PRIMARY KEY, value TEXT) '
            "ENGINE=InnoDB; INSERT INTO probe_editor VALUES (1,'editor;鸿蒙'); "
            '$_savedSource',
      ),
    );
    _require(
      written.available &&
          written.exitCode == 0 &&
          written.stdout.join('\n').contains('editor;鸿蒙'),
      'The real project SQL engine failed.',
      {'stdout': written.stdout.toList(), 'stderr': written.stderr.toList()},
    );
    final file = File(p.join(_project!.path, 'queries.json'));
    final library = await SqlQueryLibrary.open(file);
    await library.saveQuery(
      database: schema,
      name: 'probe',
      source: _savedSource,
    );
    await library.recordExecution(
      database: schema,
      source: _savedSource,
      success: true,
    );
    await _readEditor();
    return {'projectPath': _project!.path, 'savedQuery': _savedSource};
  }

  Future<void> _readEditor() async {
    final library = await SqlQueryLibrary.open(
      File(p.join(_project!.path, 'queries.json')),
    );
    _require(
      library.saved.single.database == schema &&
          library.saved.single.source == _savedSource &&
          library.history.single.success,
      'Saved SQL/history did not survive reopening their private file.',
    );
    final result = await NativeMySqlEngine(database: _database).execute(
      SqlProgramRequest(
        projectPath: _project!.path,
        source: library.saved.single.source,
      ),
    );
    _require(
      result.available &&
          result.exitCode == 0 &&
          result.stdout.join('\n').contains('editor;鸿蒙'),
      'The project marker and saved SQL failed on a fresh engine instance.',
      {'stdout': result.stdout.toList(), 'stderr': result.stderr.toList()},
    );
    _rows(await _query(_savedSource), [
      ['editor;鸿蒙'],
    ]);
  }

  Future<Map<String, Object?>> _stop() async {
    await mysqlNativeChannel
        .invokeMethod<void>('stop')
        .timeout(const Duration(seconds: 90));
    final pidFile = _pidFile;
    if (pidFile != null) {
      _require(
        !await File(pidFile).exists(),
        'stop returned while the MySQL PID file still exists.',
        {'pidFile': pidFile, 'serverPid': _serverPid},
      );
    }
    _runtimeTouched = false;
    _cleanup['runtimeStopped'] = true;
    return {'previousServerPid': _serverPid, 'pidFileRemoved': pidFile != null};
  }

  Future<Map<String, Object?>> _restart() async {
    // A fresh adapter still uses the registered production MethodChannel.
    _database = _OhosDatabase();
    final server = await _inspectServer(restarted: true);
    final values = await _readValues();
    final transactions = await _readTransactions();
    final grid = await _workspace.loadTable(schema, 'probe_grid');
    _sameRows(grid.rows, [
      [_largeId, 'grid;鸿蒙', '80FF00'],
    ]);
    await _readEditor();
    return {
      'server': server,
      'rows': values.rows,
      'transactions': transactions.rows,
      'grid': grid.rows,
      'savedQueryReopened': true,
    };
  }

  Future<Map<String, Object?>> _removeFixture() async {
    _require(
      _ownsSchema,
      'Cannot clean a schema without successful ownership.',
    );
    await _query('DROP DATABASE `$schema`', databaseName: '');
    _ownsSchema = false;
    _cleanup['schemaDropped'] = true;
    final project = _project!;
    final parent = await _runDirectory!.resolveSymbolicLinks();
    final resolved = await project.resolveSymbolicLinks();
    _require(
      p.isWithin(parent, resolved) && p.equals(p.dirname(resolved), parent),
      'Refusing cleanup outside this probe run directory.',
    );
    await project.delete(recursive: true);
    _project = null;
    _cleanup['projectRemoved'] = true;
    return {'schemaDropped': schema, 'projectRemoved': resolved};
  }

  Future<SqlQueryResult> _query(
    String source, {
    String? databaseName,
    List<String?> parameters = const [],
  }) async {
    final result = await _database.query(
      databasePath: databaseName ?? schema,
      source: source,
      parameters: parameters,
    );
    _requireResult(result);
    return result;
  }

  void _requireResult(SqlQueryResult result) => _require(
    result.success && !result.truncated,
    'Oracle query failed or was truncated.',
    _evidence(result),
  );

  void _requireScript(SqlScriptResult result) {
    _requireResult(result.summary);
    for (final entry in result.results) {
      _requireResult(entry);
    }
  }

  void _rows(SqlQueryResult result, List<List<String?>> expected) {
    _requireResult(result);
    _sameRows(result.rows, expected);
  }

  void _sameRows(List<List<String?>> actual, List<List<String?>> expected) =>
      _require(
        jsonEncode(actual) == jsonEncode(expected),
        'Oracle values differ from the exact expected rows.',
        {'expected': expected, 'actual': actual},
      );

  void _require(bool condition, String message, [Object? evidence]) {
    if (!condition) throw _ProbeFailure(message, evidence);
  }

  Map<String, Object?> _evidence(SqlQueryResult result) => {
    'available': result.available,
    'exitCode': result.exitCode,
    'sqlState': result.sqlState,
    'error': result.error,
    'columns': result.columns,
    'rows': result.rows,
    'affectedRows': result.affectedRows,
    'truncated': result.truncated,
  };

  Future<void> _check(
    String name,
    Future<Map<String, Object?>> Function() operation, {
    bool checkpointBefore = true,
  }) async {
    final started = _clock.elapsedMilliseconds;
    final check = <String, Object?>{'name': name, 'status': 'running'};
    _checks.add(check);
    _log('CHECK_START', {'name': name});
    if (checkpointBefore) await _saveReport();
    try {
      final evidence = await operation();
      check.addAll({'status': 'pass', 'evidence': evidence});
      _log('CHECK_PASS', {'name': name, 'evidence': evidence});
    } on Object catch (error, stack) {
      check.addAll({
        'status': 'fail',
        'error': error.toString(),
        'stackTrace': stack.toString(),
        if (error is _ProbeFailure) 'evidence': error.evidence,
      });
      _log('CHECK_FAIL', {
        'name': name,
        'error': error.toString(),
        if (error is _ProbeFailure) 'evidence': error.evidence,
      });
      rethrow;
    } finally {
      check['elapsedMs'] = _clock.elapsedMilliseconds - started;
      await _saveReport();
    }
  }

  Future<void> _saveReport() async {
    final file = _reportFile;
    if (file == null) return;
    final source = const JsonEncoder.withIndent('  ').convert(_report);
    for (final target in [
      file,
      File(p.join(_reportRoot!.path, 'latest.json')),
    ]) {
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(source, flush: true);
      await temporary.rename(target.path);
    }
  }

  void _log(String kind, Map<String, Object?> details) {
    final payload = jsonEncode({
      'runId': runId,
      'elapsedMs': _clock.elapsedMilliseconds,
      ...details,
    });
    // Preserve even long native initialization/loader diagnostics in hilog.
    // DETAIL chunks concatenate to the complete JSON payload for this event.
    if (utf8.encode(payload).length <= 3000) {
      debugPrintSynchronously('$_marker $kind $payload');
    } else {
      debugPrintSynchronously(
        '$_marker $kind ${jsonEncode({'runId': runId, 'detailsInReport': _reportFile?.path, 'name': details['name'], 'chunked': true})}',
      );
      const chunkSize = 400;
      final parts = (payload.length / chunkSize).ceil();
      for (var part = 0; part < parts; part++) {
        debugPrintSynchronously(
          '$_marker DETAIL ${jsonEncode({'runId': runId, 'kind': kind, 'part': part + 1, 'parts': parts, 'jsonChunk': payload.substring(part * chunkSize, min((part + 1) * chunkSize, payload.length))})}',
        );
      }
    }
    onLine('$kind $payload');
  }

  Future<String> _replay() async {
    try {
      final storage = await AppPaths.storageDirectory();
      _require(storage != null, 'App-private storage is unavailable.');
      final file = File(p.join(storage!, 'mysql-ohos-probe', 'latest.json'));
      final saved = jsonDecode(await file.readAsString());
      _require(
        saved is Map && saved['probe'] == _marker,
        'No valid previous phone probe report exists.',
      );
      _log('REPLAY', {'reportPath': file.path, 'savedReport': saved});
      return 'Saved report only · no runtime checks executed';
    } on Object catch (error) {
      _log('REPLAY_FAIL', {'error': error.toString()});
      return 'Saved report unavailable';
    }
  }
}
