import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/mysql_workspace_repository.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';

void main() {
  late _Client client;
  late MySqlWorkspaceRepository workspace;

  setUp(() {
    client = _Client();
    workspace = MySqlWorkspaceRepository(
      runtimeDirectory: Directory('unused-runtime'),
      database: client,
    );
  });

  test(
    'composite key identifies one row even when visible values repeat',
    () async {
      client.columns = [
        ['value', 'text', 'YES', ''],
        ['group', 'varchar(255)', 'NO', 'PRI'],
        ['id', 'bigint', 'NO', 'PRI'],
      ];
      client.rows = [
        ['same', "O'Brien", '9007199254740993'],
        ['same', "O'Brien", '9007199254740994'],
      ];
      final page = await workspace.loadTable('lab', 'values');
      expect(page.editable, isTrue);
      expect(page.rowIds.toSet(), hasLength(2));
      expect(jsonDecode(page.rowIds.first), [
        ['group', "O'Brien"],
        ['id', '9007199254740993'],
      ]);

      await workspace.updateCell(
        'lab',
        'values',
        page.rowIds.last,
        'value',
        null,
      );
      final update = client.calls.last;
      expect(
        update.source,
        'UPDATE `values` SET `value` = ? WHERE `group` = ? AND `id` = ?',
      );
      expect(update.parameters, [null, "O'Brien", '9007199254740994']);
      expect(update.schema, 'lab');
    },
  );

  test(
    'changed key metadata rejects old row identities before mutation',
    () async {
      final page = await workspace.loadTable('lab', 'items');
      client.columns = [
        ['new_id', 'int', 'NO', 'PRI'],
        ['value', 'text', 'YES', ''],
      ];
      await expectLater(
        workspace.deleteRow('lab', 'items', page.rowIds.first),
        throwsArgumentError,
      );
      expect(
        client.calls.where((call) => call.source.startsWith('DELETE')),
        isEmpty,
      );
    },
  );

  test(
    'table without a primary key is readable and cannot mutate rows',
    () async {
      client.columns = [
        ['value', 'text', 'YES', ''],
      ];
      client.rows = [
        ['same'],
        ['same'],
      ];
      final page = await workspace.loadTable('lab', 'items');
      expect(page.editable, isFalse);
      expect(page.rowIds, isEmpty);
      expect(page.rows, client.rows);
      await expectLater(
        workspace.deleteRow('lab', 'items', '["same"]'),
        throwsStateError,
      );
      await workspace.insertRow('lab', 'items', {'value': 'new'});
      expect(client.calls.last.parameters, ['new']);
    },
  );

  test('paging adds primary-key tie breakers and binds filter text', () async {
    await workspace.loadTable(
      'lab',
      'items',
      page: 2,
      filterColumn: 'value',
      filter: "'; DROP TABLE items; --",
      sortColumn: 'value',
      descending: true,
    );
    final select = client.calls.last;
    expect(select.source, contains('ORDER BY `value` DESC, `id` ASC'));
    expect(select.source, endsWith('LIMIT 100 OFFSET 200'));
    expect(select.source, isNot(contains('DROP TABLE')));
    expect(select.parameters, ["%'; DROP TABLE items; --%"]);
  });

  test('truncation or unmatched mutations are failures', () async {
    client.truncated = true;
    await expectLater(workspace.loadTable('lab', 'items'), throwsStateError);
    client.truncated = false;
    final page = await workspace.loadTable('lab', 'items');
    client.affectedRows = 0;
    await expectLater(
      workspace.updateCell(
        'lab',
        'items',
        page.rowIds.first,
        'value',
        'changed',
      ),
      throwsStateError,
    );
  });

  test(
    'quotes MySQL identifiers and creates an auto-increment integer key',
    () async {
      await workspace.createTable('lab', 'odd`table', const [
        SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
        SqlColumnDraft(name: 'payload', type: 'VARCHAR(255)'),
      ]);
      expect(
        client.calls.single.source,
        'CREATE TABLE `odd``table` (`id` INTEGER NOT NULL AUTO_INCREMENT, '
        '`payload` VARCHAR(255), PRIMARY KEY (`id`)) ENGINE = InnoDB',
      );
      expect(() => workspace.databasePath('x\u0000y'), throwsArgumentError);
      await expectLater(workspace.deleteDatabase('MYSQL'), throwsArgumentError);
    },
  );

  test('Oracle errors reach callers without a successful result', () async {
    client.error = 'Unknown database';
    await expectLater(
      workspace.listTables('missing'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unknown database',
        ),
      ),
    );
  });
}

class _Call {
  _Call(this.schema, this.source, this.parameters);

  final String schema;
  final String source;
  final List<String?> parameters;
}

class _Client implements SqlDatabase {
  final calls = <_Call>[];
  List<List<String?>> columns = [
    ['id', 'int', 'NO', 'PRI'],
    ['value', 'text', 'YES', ''],
  ];
  List<List<String?>> rows = [
    ['1', 'original'],
  ];
  int affectedRows = 1;
  bool truncated = false;
  String? error;

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async {
    calls.add(_Call(databasePath, source, parameters));
    final isMetadata = source.contains('information_schema.COLUMNS');
    final isCount = source.startsWith('SELECT COUNT');
    return SqlQueryResult(
      available: true,
      exitCode: error == null ? 0 : 1,
      columns: isMetadata
          ? ['COLUMN_NAME', 'COLUMN_TYPE', 'IS_NULLABLE', 'COLUMN_KEY']
          : isCount
          ? ['COUNT(*)']
          : [for (final column in columns) column.first!],
      rows: isMetadata
          ? columns
          : isCount
          ? [
              ['${rows.length}'],
            ]
          : rows,
      affectedRows: affectedRows,
      truncated: truncated,
      error: error,
    );
  }
}
