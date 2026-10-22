import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_code_analyzer.dart';

void main() {
  Map<String, Object?> response() => {
    'available': true,
    'engine': 'sqlite',
    'version': '3.50.0',
    'statements': 1,
    'checked': 1,
    'schemaGaps': 0,
    'truncated': false,
    'issues': <Object?>[],
    'skipped': <Object?>[],
    'error': '',
  };

  test('an unknown or damaged backend response cannot report clean', () {
    for (final change in <Map<String, Object?>>[
      {'engine': 'mysql'},
      {'available': null},
      {'version': ''},
      {'checked': 1.2},
      {'checked': 2},
      {'schemaGaps': 2},
      {
        'issues': [null],
      },
      {
        'issues': [
          {'startOffset': -1, 'endOffset': 1},
        ],
      },
      {
        'skipped': [
          {'startOffset': 0, 'endOffset': 100},
        ],
      },
      {'truncated': null},
      {'error': 0},
    ]) {
      expect(
        () => SqlitePrepareSyntaxEngine.decodeResult({
          ...response(),
          ...change,
        }, 'SELECT 1;'),
        throwsFormatException,
        reason: change.toString(),
      );
    }
    expect(
      () => SqlitePrepareSyntaxEngine.decodeResult({}, 'SELECT 1;'),
      throwsFormatException,
    );
  });

  test('zero checked SQL differs from empty or trivia-only input', () {
    final empty = {...response(), 'statements': 0, 'checked': 0};
    for (final text in ['', ' -- only a comment\r\n', '/* comment */ ;']) {
      expect(
        SqlitePrepareSyntaxEngine.decodeResult(empty, text).unavailableReason,
        isNull,
      );
    }
    for (final text in ['SELECT 1;', "SELECT 'open", '/* open']) {
      expect(
        () => SqlitePrepareSyntaxEngine.decodeResult(empty, text),
        throwsFormatException,
      );
    }
    expect(
      () => SqlitePrepareSyntaxEngine.decodeResult({
        ...response(),
        'checked': 0,
      }, 'SELECT 1;'),
      throwsFormatException,
    );
  });

  test('partial and unavailable coverage stays visible', () {
    final partial = SqlitePrepareSyntaxEngine.decodeResult({
      ...response(),
      'statements': 2,
    }, 'SELECT 1; SELECT 2;');
    expect(partial.unavailableReason, contains('1/2'));
    final unavailable = SqlitePrepareSyntaxEngine.decodeResult({
      ...response(),
      'available': false,
      'checked': 0,
      'error': 'bridge absent',
    }, 'SELECT 1;');
    expect(unavailable.unavailableReason, 'bridge absent');
    final blocked = SqlitePrepareSyntaxEngine.decodeResult({
      ...response(),
      'checked': 0,
      'skipped': [
        {
          'startOffset': 0,
          'endOffset': 6,
          'keyword': 'PRAGMA',
          'reason': 'not prepared',
        },
      ],
    }, 'PRAGMA;');
    expect(blocked.skipped.single.reason, 'not prepared');
  });

  test('UTF-16 ranges and backend severity survive decoding', () {
    const text = "SELECT '😀', FROM;";
    final start = text.indexOf('FROM');
    final result = SqlitePrepareSyntaxEngine.decodeResult({
      ...response(),
      'issues': [
        {
          'startOffset': start,
          'endOffset': start + 4,
          'message': 'syntax error',
          'code': 'sqlite-syntax-offset',
          'severity': 'error',
        },
      ],
    }, text);
    expect(
      text.substring(
        result.issues.single.startOffset,
        result.issues.single.endOffset,
      ),
      'FROM',
    );
  });
}
