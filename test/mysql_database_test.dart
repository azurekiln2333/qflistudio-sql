import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/mysql_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_sql/mysql_test');
  const database = NativeMySqlDatabase(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> response() => {
    'available': true,
    'exitCode': 0,
    'error': '',
    'sqlState': '',
    'affectedRows': 0,
    'truncated': false,
    'columns': ['id', 'bytes'],
    'columnInfo': [
      {'name': 'id', 'nativeType': 8, 'binary': false},
      {'name': 'bytes', 'nativeType': 252, 'binary': true},
    ],
    'rows': [
      ['9007199254740993', null],
    ],
  };

  test(
    'forwards a schema and bound values and retains Oracle column metadata',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'query');
        expect(call.arguments, {
          'schema': 'lab',
          'source': 'SELECT ?, ?',
          'params': ["O'Brien", null],
        });
        return response();
      });
      final result = await database.query(
        databasePath: 'lab',
        source: 'SELECT ?, ?',
        parameters: ["O'Brien", null],
      );
      expect(result.success, isTrue);
      expect(result.rows.single, ['9007199254740993', null]);
      expect(result.columnInfo.last.binary, isTrue);
      expect(result.columnInfo.last.nativeType, 252);
    },
  );

  test('server operations can use an empty schema', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect((call.arguments as Map)['schema'], '');
      return response();
    });
    expect(
      (await database.query(
        databasePath: '',
        source: 'SHOW DATABASES',
      )).success,
      isTrue,
    );
  });

  test('preserves actual MySQL error number and SQLSTATE', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        ...response(),
        'exitCode': 1064,
        'sqlState': '42000',
        'error': 'Syntax error',
      },
    );
    final result = await database.query(databasePath: 'lab', source: 'wrong');
    expect(result.available, isTrue);
    expect(result.success, isFalse);
    expect(result.exitCode, 1064);
    expect(result.sqlState, '42000');
    expect(result.error, 'Syntax error');
  });

  test('rejects mismatched column metadata', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        ...response(),
        'columnInfo': [
          {'name': 'other', 'nativeType': 8, 'binary': false},
        ],
      },
    );
    final result = await database.query(
      databasePath: 'lab',
      source: 'SELECT 1',
    );
    expect(result.available, isFalse);
    expect(result.success, isFalse);
  });

  test('missing plugin never reports a successful MySQL query', () async {
    final result = await database.query(
      databasePath: 'lab',
      source: 'SELECT 1',
    );
    expect(result.available, isFalse);
    expect(result.exitCode, 127);
    expect(result.error, contains('Oracle MySQL'));
  });
}
