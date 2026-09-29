import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_runner.dart';

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
}
