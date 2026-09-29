import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
}
