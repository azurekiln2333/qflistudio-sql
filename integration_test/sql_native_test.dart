import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_runner.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native SQLite persists rows and reports SQL errors', (
    tester,
  ) async {
    final project = await Directory.systemTemp.createTemp('qfli_sql_device_');
    addTearDown(() => project.delete(recursive: true));
    const engine = NativeSqliteEngine();

    final write = await engine.execute(
      SqliteRequest(
        projectPath: project.path,
        source:
            'CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL); '
            "INSERT INTO people (name) VALUES ('Ada');",
      ),
    );
    expect(write.available, isTrue, reason: write.stderr.join('\n'));
    expect(write.exitCode, 0, reason: write.stderr.join('\n'));

    final read = await engine.execute(
      SqliteRequest(
        projectPath: project.path,
        source: 'SELECT id, name FROM people;',
      ),
    );
    expect(read.exitCode, 0, reason: read.stderr.join('\n'));
    expect(read.stdout, ['1\tAda']);

    final invalid = await engine.execute(
      SqliteRequest(
        projectPath: project.path,
        source: 'SELECT missing FROM people;',
      ),
    );
    expect(invalid.available, isTrue);
    expect(invalid.exitCode, isNonZero);
    expect(invalid.stderr.join('\n'), contains('missing'));
  });

  testWidgets('structured queries bind values and preserve NULL', (
    tester,
  ) async {
    final project = await Directory.systemTemp.createTemp('qfli_grid_device_');
    addTearDown(() => project.delete(recursive: true));
    final path = p.join(project.path, 'data.sqlite');
    const database = NativeSqliteDatabase();

    final schema = await database.query(
      databasePath: path,
      source:
          'CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, note TEXT)',
    );
    expect(schema.success, isTrue, reason: schema.error);

    final write = await database.query(
      databasePath: path,
      source: 'INSERT INTO people (name, note) VALUES (?, ?)',
      parameters: ["O'Brien", null],
    );
    expect(write.success, isTrue, reason: write.error);
    expect(write.affectedRows, 1);

    final read = await database.query(
      databasePath: path,
      source: 'SELECT id, name, note FROM people WHERE name = ?',
      parameters: ["O'Brien"],
    );
    expect(read.success, isTrue, reason: read.error);
    expect(read.columns, ['id', 'name', 'note']);
    expect(read.rows, [
      ['1', "O'Brien", null],
    ]);

    final multiple = await database.query(
      databasePath: path,
      source: 'SELECT 1; SELECT 2;',
    );
    expect(multiple.success, isFalse);
    expect(multiple.error, contains('Only one SQL statement'));
  });

  testWidgets('workspace creates and edits a real database', (tester) async {
    final root = await Directory.systemTemp.createTemp(
      'qfli_workspace_device_',
    );
    addTearDown(() => root.delete(recursive: true));
    final workspace = SqlWorkspaceRepository(root: root);

    await workspace.createDatabase('work');
    expect(await workspace.listDatabases(), ['work']);
    await workspace.createTable('work', 'people', const [
      SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
      SqlColumnDraft(name: 'name', type: 'TEXT', notNull: true),
      SqlColumnDraft(name: 'note', type: 'TEXT'),
    ]);
    expect(await workspace.listTables('work'), ['people']);

    await workspace.insertRow('work', 'people', {
      'name': "O'Brien",
      'note': null,
    });
    var page = await workspace.loadTable('work', 'people');
    expect(page.totalRows, 1);
    expect(page.editable, isTrue);
    expect(page.rows, [
      ['1', "O'Brien", null],
    ]);

    await workspace.updateCell(
      'work',
      'people',
      page.rowIds.single,
      'note',
      'ok',
    );
    page = await workspace.loadTable(
      'work',
      'people',
      filterColumn: 'name',
      filter: "O'B",
      sortColumn: 'id',
    );
    expect(page.rows, [
      ['1', "O'Brien", 'ok'],
    ]);

    await workspace.deleteRow('work', 'people', page.rowIds.single);
    expect((await workspace.loadTable('work', 'people')).totalRows, 0);
    await workspace.deleteTable('work', 'people');
    expect(await workspace.listTables('work'), isEmpty);
    await workspace.deleteDatabase('work');
    expect(await workspace.listDatabases(), isEmpty);
  });

  testWidgets('grid identity is not shadowed by a user rowid column', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('qfli_rowid_device_');
    addTearDown(() => root.delete(recursive: true));
    final workspace = SqlWorkspaceRepository(root: root);
    await workspace.createDatabase('work');
    await workspace.createTable('work', 'items', const [
      SqlColumnDraft(name: 'rowid', type: 'TEXT'),
      SqlColumnDraft(name: 'name', type: 'TEXT'),
    ]);
    await workspace.insertRow('work', 'items', {
      'rowid': 'same',
      'name': 'one',
    });
    await workspace.insertRow('work', 'items', {
      'rowid': 'same',
      'name': 'two',
    });
    var page = await workspace.loadTable('work', 'items');
    expect(page.rowIds, ['1', '2']);
    await workspace.updateCell(
      'work',
      'items',
      page.rowIds.first,
      'name',
      'edit',
    );
    page = await workspace.loadTable('work', 'items');
    expect(page.rows, [
      ['same', 'edit'],
      ['same', 'two'],
    ]);
    await workspace.deleteRow('work', 'items', page.rowIds.first);
    expect((await workspace.loadTable('work', 'items')).rows, [
      ['same', 'two'],
    ]);
  });

  testWidgets('tables without an accessible rowid are read only', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('qfli_readonly_device_');
    addTearDown(() => root.delete(recursive: true));
    final workspace = SqlWorkspaceRepository(root: root);
    await workspace.createDatabase('work');
    final created = await workspace.runQuery(
      'work',
      'CREATE TABLE items (id TEXT PRIMARY KEY) WITHOUT ROWID',
    );
    expect(created.success, isTrue, reason: created.error);
    await workspace.insertRow('work', 'items', {'id': 'one'});
    final page = await workspace.loadTable('work', 'items');
    expect(page.editable, isFalse);
    expect(page.rowIds, isEmpty);
    expect(page.rows, [
      ['one'],
    ]);
  });
}
