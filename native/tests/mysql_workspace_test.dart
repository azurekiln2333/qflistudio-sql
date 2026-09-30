import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/mysql_workspace_repository.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';

void main() {
  final bridge = Platform.environment['QFLI_MYSQL_TEST_BRIDGE'];
  final socket = Platform.environment['QFLI_MYSQL_TEST_SOCKET'];
  if (bridge == null || socket == null) {
    throw StateError('Set QFLI_MYSQL_TEST_BRIDGE and QFLI_MYSQL_TEST_SOCKET');
  }
  final client = _HostClient(bridge, socket);
  final workspace = MySqlWorkspaceRepository(
    runtimeDirectory: Directory('unused-host-runtime'),
    database: client,
  );
  late String schema;

  setUp(() async {
    schema = 'qfli_workspace_test_${DateTime.now().microsecondsSinceEpoch}';
    await workspace.createDatabase(schema);
  });

  tearDown(() => workspace.deleteDatabase(schema));

  test(
    'database, table, auto-increment rows and NULL round-trip on Oracle',
    () async {
      expect(await workspace.listDatabases(), contains(schema));
      await workspace.createTable(schema, 'odd`table', const [
        SqlColumnDraft(name: 'id', type: 'BIGINT', primaryKey: true),
        SqlColumnDraft(name: 'name', type: 'VARCHAR(255)'),
        SqlColumnDraft(name: 'note', type: 'TEXT'),
      ]);
      expect(await workspace.listTables(schema), ['odd`table']);
      await workspace.insertRow(schema, 'odd`table', {
        'id': null,
        'name': "O'Brien",
        'note': null,
      });
      var page = await workspace.loadTable(schema, 'odd`table');
      expect(page.totalRows, 1);
      expect(page.rows.single, ['1', "O'Brien", null]);
      await workspace.updateCell(
        schema,
        'odd`table',
        page.rowIds.single,
        'name',
        '中文',
      );
      page = await workspace.loadTable(schema, 'odd`table');
      expect(page.rows.single[1], '中文');
      await workspace.updateCell(
        schema,
        'odd`table',
        page.rowIds.single,
        'name',
        '中文',
      );
      await workspace.deleteRow(schema, 'odd`table', page.rowIds.single);
      expect((await workspace.loadTable(schema, 'odd`table')).totalRows, 0);
      await workspace.deleteTable(schema, 'odd`table');
      expect(await workspace.listTables(schema), isEmpty);
    },
  );

  test(
    'composite and binary primary keys preserve exact row identity',
    () async {
      final result = await workspace.runQuery(
        schema,
        'CREATE TABLE items (bytes VARBINARY(16), id BIGINT, '
        'amount DECIMAL(30,6), PRIMARY KEY(bytes, id))',
      );
      expect(result.success, isTrue);
      for (final id in ['9007199254740993', '9007199254740994']) {
        await workspace.insertRow(schema, 'items', {
          'bytes': '00FF4142',
          'id': id,
          'amount': '123456789012345678901234.123456',
        });
      }
      var page = await workspace.loadTable(schema, 'items');
      expect(page.rows.first, [
        '00FF4142',
        '9007199254740993',
        '123456789012345678901234.123456',
      ]);
      await workspace.updateCell(
        schema,
        'items',
        page.rowIds.last,
        'amount',
        '0.1',
      );
      page = await workspace.loadTable(schema, 'items');
      expect(page.rows.first.last, '123456789012345678901234.123456');
      expect(page.rows.last.last, '0.100000');
      await workspace.deleteRow(schema, 'items', page.rowIds.first);
      expect(
        (await workspace.loadTable(schema, 'items')).rows.single[1],
        '9007199254740994',
      );
    },
  );

  test(
    'BLOB bytes, empty bytes and NULL are different editable values',
    () async {
      await workspace.createTable(schema, 'bytes', const [
        SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
        SqlColumnDraft(name: 'value', type: 'BLOB'),
      ]);
      await workspace.insertRow(schema, 'bytes', {'value': '00FF41'});
      var page = await workspace.loadTable(schema, 'bytes');
      expect(page.rows.single[1], '00FF41');
      await workspace.updateCell(
        schema,
        'bytes',
        page.rowIds.single,
        'value',
        '',
      );
      page = await workspace.loadTable(schema, 'bytes');
      expect(page.rows.single[1], '');
      await workspace.updateCell(
        schema,
        'bytes',
        page.rowIds.single,
        'value',
        null,
      );
      expect(
        (await workspace.loadTable(schema, 'bytes')).rows.single[1],
        isNull,
      );
      await expectLater(
        workspace.insertRow(schema, 'bytes', {'value': 'not hex'}),
        throwsArgumentError,
      );
    },
  );

  test(
    'filter, sort, offset and read-only tables query real metadata',
    () async {
      expect(
        (await workspace.runQuery(
          schema,
          'CREATE TABLE items (id INT PRIMARY KEY, name TEXT)',
        )).success,
        isTrue,
      );
      final inserted = await workspace.runQuery(
        schema,
        'INSERT INTO items WITH RECURSIVE seq(n) AS '
        '(SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 210) '
        "SELECT n, IF(n % 2 = 0, 'even', 'odd') FROM seq",
      );
      expect(inserted.success, isTrue, reason: inserted.error);
      final page = await workspace.loadTable(
        schema,
        'items',
        page: 1,
        filterColumn: 'name',
        filter: 'even',
        sortColumn: 'id',
        descending: true,
      );
      expect(page.totalRows, 105);
      expect(page.rows, [
        ['10', 'even'],
        ['8', 'even'],
        ['6', 'even'],
        ['4', 'even'],
        ['2', 'even'],
      ]);
      expect(
        (await workspace.runQuery(
          schema,
          'CREATE TABLE no_key (name TEXT)',
        )).success,
        isTrue,
      );
      await workspace.insertRow(schema, 'no_key', {'name': 'readable'});
      final readOnly = await workspace.loadTable(schema, 'no_key');
      expect(readOnly.editable, isFalse);
      expect(readOnly.rows.single, ['readable']);
      expect(
        (await workspace.runQuery(schema, 'SELEC wrong')).success,
        isFalse,
      );
    },
  );
}

class _HostClient implements SqlDatabase {
  _HostClient(this.bridge, this.socket);

  final String bridge;
  final String socket;

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async {
    final process = await Process.start('wsl.exe', [
      '-d',
      'qfli-java-build',
      '--',
      bridge,
      socket,
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(
      jsonEncode({
        'schema': databasePath,
        'source': source,
        'params': parameters,
      }),
    );
    await process.stdin.close();
    final exit = await process.exitCode;
    if (exit != 0) {
      throw StateError('Host MySQL bridge failed: ${await errors}');
    }
    final raw = jsonDecode(await output) as Map<String, dynamic>;
    final message = raw['error'] as String;
    return SqlQueryResult(
      available: raw['available'] as bool,
      exitCode: raw['exitCode'] as int,
      columns: List<String>.from(raw['columns'] as List),
      rows: [
        for (final row in raw['rows'] as List) List<String?>.from(row as List),
      ],
      affectedRows: raw['affectedRows'] as int,
      truncated: raw['truncated'] as bool,
      error: message.isEmpty ? null : message,
    );
  }
}
