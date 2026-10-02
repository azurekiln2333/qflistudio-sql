import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'package:qfli_sql/local_mysql_runtime.dart';
import 'package:qfli_sql/mysql_ffi.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError('FAIL: $message');
}

void success(Map<String, Object?> result) {
  require(result['available'] == true && result['exitCode'] == 0, '$result');
}

Future<void> main(List<String> arguments) async {
  final orphan = arguments.first == '--parent-server';
  final args = orphan ? arguments.sublist(1) : arguments;
  require(args.length >= 3, 'pass bundle, bridge library and launcher');
  final root = orphan
      ? Directory(args[3])
      : await Directory.systemTemp.createTemp('qfli-mysql-test-');
  LocalMySqlRuntime createRuntime() => LocalMySqlRuntime(
    bundleDirectory: Directory(args[0]),
    dataDirectory: root,
    libraryPath: args[1],
    launcherPath: args[2],
    serverPath: Platform.environment['QFLI_MYSQL_TEST_SERVER'],
    serverUser: Platform.environment['QFLI_MYSQL_TEST_USER'],
  );
  var runtime = createRuntime();
  Future<Map<String, Object?>> query(
    String source, [
    List<String?> params = const [],
    String schema = 'lab',
  ]) => runtime.invoke('query', {
    'schema': schema,
    'source': source,
    'params': params,
  });
  Future<Map<String, Object?>> script(String source) =>
      runtime.invoke('executeScript', {'schema': 'lab', 'source': source});
  if (orphan) {
    final result = await query('SELECT @@socket, @@pid_file', [], '');
    success(result);
    final values = (result['rows'] as List).single as List;
    final serverPid = int.parse(
      (await File(values[1] as String).readAsString()).trim(),
    );
    stdout.writeln(
      'READY ${jsonEncode({'socket': values[0], 'pid': serverPid})}',
    );
    await Future<void>.delayed(const Duration(minutes: 20));
    await runtime.stop();
    return;
  }
  var passed = 0;
  void pass(String label) {
    passed++;
    stdout.writeln('PASS $label');
  }

  try {
    final version = await query(
      'SELECT VERSION(), @@version_comment, @@skip_networking',
      [],
      '',
    );
    success(version);
    require(
      RegExp(r'^8\.\d+\.\d+').hasMatch(
            ((version['rows'] as List).single as List).first as String,
          ) &&
          !version.toString().contains('MariaDB'),
      'real Oracle engine',
    );
    require(
      ((version['rows'] as List).single as List)[2] == '1',
      'TCP disabled',
    );
    pass('actual upstream initialization and private transport');

    final duplicate = createRuntime();
    final locked = await duplicate.invoke('query', {
      'schema': '',
      'source': 'SELECT 1',
      'params': <String?>[],
    });
    require(
      locked['available'] == false &&
          locked['error'].toString().contains('already in use'),
      'duplicate owner rejected',
    );
    await duplicate.stop();
    pass('exclusive data-directory ownership');

    success(await query('CREATE DATABASE lab', [], ''));
    success(
      await query(
        'CREATE TABLE items (id BIGINT PRIMARY KEY, amount DECIMAL(30,6), note TEXT, bytes BLOB)',
      ),
    );
    success(
      await query('INSERT INTO items VALUES (?, ?, ?, UNHEX(?))', [
        '9007199254740993',
        '123456789012345678901234.123456',
        "O'Brien\u4e2d\u6587",
        '00FF4142',
      ]),
    );
    final selected = await query(
      'SELECT id, amount, note, bytes, NULL FROM items',
    );
    success(selected);
    final row = (selected['rows'] as List).single as List;
    require(
      row[0] == '9007199254740993' &&
          row[1] == '123456789012345678901234.123456',
      'exact numeric values',
    );
    require(
      row[2] == "O'Brien\u4e2d\u6587" && row[3] == '00FF4142' && row[4] == null,
      'UTF-8 binary and NULL',
    );
    pass('prepared values, exact BIGINT/DECIMAL, UTF-8, binary and NULL');

    final unchanged = await query('UPDATE items SET note=? WHERE id=?', [
      row[2] as String,
      row[0] as String,
    ]);
    success(unchanged);
    require(unchanged['affectedRows'] == 1, 'matched unchanged update');
    final mismatch = await query('SELECT ?');
    require(
      mismatch['available'] == true && mismatch['exitCode'] != 0,
      'parameter mismatch rejected',
    );
    final syntax = await query('SELEC invalid');
    require(
      syntax['available'] == true &&
          syntax['exitCode'] == 1064 &&
          syntax['sqlState'] == '42000',
      'SQL diagnostics',
    );
    final multiple = await query('SELECT 1; DROP TABLE items');
    require(
      multiple['available'] == true && multiple['exitCode'] != 0,
      'query is one prepared statement',
    );
    pass('matched-row counts and real Oracle errors');

    final transaction = await script(
      'START TRANSACTION; UPDATE items SET note="rolled back"; ROLLBACK; SELECT note FROM items;',
    );
    success(transaction);
    require(
      transaction['results'] is List &&
          (transaction['results'] as List).length == 4,
      'ordered script results',
    );
    final afterRollback = await query('SELECT note FROM items');
    require(
      ((afterRollback['rows'] as List).single as List).single == row[2],
      'transaction rollback',
    );
    final partial = await script(
      'INSERT INTO items VALUES (2, 1, NULL, NULL); SELEC bad; INSERT INTO items VALUES (3, 1, NULL, NULL);',
    );
    require(
      partial['available'] == true && partial['exitCode'] == 1064,
      'partial script failure',
    );
    final count = await query('SELECT COUNT(*) FROM items');
    require(
      ((count['rows'] as List).single as List).single == '2',
      'earlier statements executed; later ones did not',
    );
    pass('multi-statements, rollback and partial failure');

    final limited = await runtime.invoke('query', {
      'schema': 'lab',
      'source': 'SELECT id FROM items ORDER BY id',
      'params': <String?>[],
      'rowLimit': 1,
    });
    success(limited);
    require(
      limited['truncated'] == true && (limited['rows'] as List).length == 1,
      'row cap',
    );
    final drained = await script(
      '${List.filled(130, 'SELECT 1;').join()} UPDATE items SET note="after cap" WHERE id=2;',
    );
    success(drained);
    require(
      drained['truncated'] == true &&
          (drained['results'] as List).length == 128,
      'result-set cap',
    );
    final afterCap = await query('SELECT note FROM items WHERE id=2');
    require(
      ((afterCap['rows'] as List).single as List).single == 'after cap',
      'execution continues after display cap',
    );
    pass('display caps and complete native result draining');

    final transportResult = await query('SELECT @@socket', [], '');
    final socket = ((transportResult['rows'] as List).single as List).single;
    final unauthorized = await MySqlFfi.invoke(args[1], {
      'method': 'query',
      'socket': socket,
      'password': '',
      'schema': '',
      'source': 'SELECT 1',
      'params': <String?>[],
    });
    require(
      unauthorized['available'] == false && unauthorized['exitCode'] == 1045,
      'empty password denied',
    );
    final missing = await MySqlFfi.invoke(args[1], {
      'method': 'query',
      'socket': '$socket.missing',
      'password': '',
      'schema': '',
      'source': 'SELECT 1',
      'params': <String?>[],
    });
    require(
      missing['available'] == false && missing['exitCode'] != 0,
      'no TCP fallback',
    );
    pass('private credentials and absent transport failure');

    await runtime.stop();
    runtime = createRuntime();
    final persisted = await query(
      'SELECT id, amount, bytes FROM items WHERE id=9007199254740993',
    );
    success(persisted);
    require(
      ((persisted['rows'] as List).single as List).join('|') ==
          '9007199254740993|123456789012345678901234.123456|00FF4142',
      'persistent data after new runtime',
    );
    final queued = query('SELECT SLEEP(0.2)');
    final stopped = runtime.stop();
    success(await queued);
    await stopped;
    success(await query('SELECT 1'));
    await runtime.stop();
    pass('persistence, serialized queries, shutdown and restart');

    final marker = File(p.join(root.path, 'initialized.json'));
    final original = await marker.readAsString();
    final metadata = jsonDecode(original) as Map<String, dynamic>;
    await marker.writeAsString(jsonEncode({...metadata, 'version': '8.0.0'}));
    final invalid = await query('SELECT 1');
    require(
      invalid['available'] == false &&
          invalid['error'].toString().contains('version does not match'),
      'version mismatch rejected',
    );
    await marker.writeAsString(original);
    pass('version mismatch prevents implicit database upgrade');

    final child = await Process.start(Platform.resolvedExecutable, [
      '--packages=${(await Isolate.packageConfig)!.toFilePath()}',
      Platform.script.toFilePath(),
      '--parent-server',
      ...args.take(3),
      root.path,
    ]);
    final childErrors = child.stderr.transform(utf8.decoder).join();
    late final String ready;
    try {
      ready = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 60));
    } on Object {
      child.kill(ProcessSignal.sigkill);
      final status = await child.exitCode;
      throw StateError(
        'Parent-exit fixture failed ($status): ${await childErrors}',
      );
    }
    require(ready.startsWith('READY '), 'child server ready: $ready');
    final info = jsonDecode(ready.substring(6)) as Map;
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    await childErrors;
    var exited = false;
    for (var attempt = 0; attempt < 100; attempt++) {
      final disconnected = await MySqlFfi.invoke(args[1], {
        'method': 'query',
        'socket': info['socket'],
        'password': metadata['password'],
        'schema': '',
        'source': 'SELECT 1',
        'params': <String?>[],
      });
      if (disconnected['available'] == false) {
        exited = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    require(exited, 'native server stopped after app death');
    pass('native launcher cleans server on abrupt application exit');
    final recovery = await query('SELECT COUNT(*) FROM items');
    success(recovery);
    require(
      ((recovery['rows'] as List).single as List).single == '2',
      'InnoDB data recovered after application death',
    );
    await runtime.stop();
    pass('persistent InnoDB data recovers after abrupt exit');
    stdout.writeln(
      '$passed/$passed Oracle lifecycle checks passed on ${Platform.operatingSystem}.',
    );
  } finally {
    await runtime.stop();
    // Keep real-engine data/logs for inspection rather than deleting evidence.
    stdout.writeln('Fixture: ${root.path}');
  }
}
