import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_sql/query_test');
  const database = NativeSqliteDatabase(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('decodes nullable rows and forwards bound parameters', () async {
    final directory = await Directory.systemTemp.createTemp('qfli_query_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'nested', 'data.sqlite');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'query');
      expect(call.arguments, {
        'source': 'SELECT ? AS name, ? AS note',
        'databasePath': path,
        'params': ["O'Brien", null],
      });
      expect(Directory(p.dirname(path)).existsSync(), isTrue);
      return {
        'available': true,
        'exitCode': 0,
        'error': '',
        'columns': ['name', 'note'],
        'rows': [
          ["O'Brien", null],
        ],
        'affectedRows': 0,
        'truncated': false,
      };
    });

    final result = await database.query(
      databasePath: path,
      source: 'SELECT ? AS name, ? AS note',
      parameters: ["O'Brien", null],
    );
    expect(result.success, isTrue);
    expect(result.columns, ['name', 'note']);
    expect(result.rows, [
      ["O'Brien", null],
    ]);
  });

  test('rejects malformed row shapes', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'available': true,
        'exitCode': 0,
        'error': '',
        'columns': ['id'],
        'rows': [
          ['1', 'unexpected'],
        ],
        'affectedRows': 0,
        'truncated': false,
      },
    );

    final result = await database.query(
      databasePath: ':memory:',
      source: 'SELECT 1',
    );
    expect(result.success, isFalse);
    expect(result.available, isFalse);
    expect(result.exitCode, 127);
  });
}
