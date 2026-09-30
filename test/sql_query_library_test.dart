import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_query_library.dart';

void main() {
  test('history and saved queries survive reopening the library', () async {
    final directory = await Directory.systemTemp.createTemp('qfli_queries_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sql_queries.json');
    final library = await SqlQueryLibrary.open(file);

    await library.recordExecution(
      database: 'work',
      source: 'SELECT * FROM people',
      success: true,
    );
    await library.recordExecution(
      database: 'work',
      source: 'SELECT bad',
      success: false,
    );
    await library.saveQuery(
      database: 'work',
      name: 'People',
      source: 'SELECT * FROM people',
    );
    await library.saveQuery(
      database: 'work',
      name: 'People',
      source: 'SELECT name FROM people',
    );

    final reopened = await SqlQueryLibrary.open(file);
    expect(reopened.history.map((item) => item.success), [false, true]);
    expect(reopened.history.first.source, 'SELECT bad');
    expect(reopened.saved, hasLength(1));
    expect(reopened.saved.single.source, 'SELECT name FROM people');

    await reopened.deleteSavedQuery('work', 'People');
    await reopened.clearHistory();
    final cleared = await SqlQueryLibrary.open(file);
    expect(cleared.history, isEmpty);
    expect(cleared.saved, isEmpty);
  });

  test('invalid persisted data is reported instead of discarded', () async {
    final directory = await Directory.systemTemp.createTemp('qfli_queries_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sql_queries.json');
    await file.writeAsString('{invalid');

    await expectLater(SqlQueryLibrary.open(file), throwsFormatException);
    expect(await file.readAsString(), '{invalid');
  });

  test(
    'a failed write does not publish a saved query or history entry',
    () async {
      final directory = await Directory.systemTemp.createTemp('qfli_queries_');
      addTearDown(() => directory.delete(recursive: true));
      final destination = Directory('${directory.path}/sql_queries.json');
      await destination.create();
      final library = SqlQueryLibrary(file: File(destination.path));

      await expectLater(
        library.saveQuery(database: 'work', name: 'People', source: 'SELECT 1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(library.saved, isEmpty);
      await expectLater(
        library.recordExecution(
          database: 'work',
          source: 'SELECT 1',
          success: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(library.history, isEmpty);
    },
  );
}
