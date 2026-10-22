import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_syntax_validator.dart';

/// Asserts the shared half-open UTF-16 contract for every produced range.
void expectBounded(SqlLexicalAnalysis analysis, String text) {
  for (final issue in analysis.issues) {
    expect(issue.start, inInclusiveRange(0, text.length), reason: issue.code);
    expect(issue.end, inInclusiveRange(issue.start, text.length));
  }
}

List<String> codes(SqlLexicalAnalysis analysis) => [
  for (final issue in analysis.issues) issue.code,
];

void main() {
  group('tokenizer', () {
    test('reproduces the exact source, including Chinese, emoji and CRLF', () {
      const text =
          "SELECT '中文😀' AS a, \"b\" FROM t; -- 注释\r\n"
          "/* 多行\r\n注释 */ SELECT 2;";
      final tokens = SqlSyntaxValidator.tokenize(text);
      expect(tokens.map((token) => token.text).join(), text);
      expect(tokens.first.kind, SqlTokenKind.word);
      expect(
        tokens.where((token) => token.kind == SqlTokenKind.string).length,
        1,
      );
      expect(
        tokens.where((token) => token.kind == SqlTokenKind.lineComment).length,
        1,
      );
      expect(
        tokens.where((token) => token.kind == SqlTokenKind.blockComment).length,
        1,
      );
    });

    test('keeps dialect quoting rules distinct', () {
      const text = 'SELECT "a", `b`, [c] FROM t';
      expect(
        SqlSyntaxValidator.tokenize(text)
            .where((token) => token.kind == SqlTokenKind.identifier)
            .map((token) => token.text),
        ['"a"', '`b`', '[c]'],
      );
      // MySQL treats double quotes as string literals by default.
      expect(
        SqlSyntaxValidator.tokenize(
          text,
          dialect: SqlDialect.mysql,
        ).firstWhere((token) => token.text == '"a"').kind,
        SqlTokenKind.string,
      );
      // MySQL has no bracket identifiers, so `[c]` is not one token.
      expect(
        SqlSyntaxValidator.tokenize(
          text,
          dialect: SqlDialect.mysql,
        ).where((token) => token.text == '[c]'),
        isEmpty,
      );
    });

    test('tokenizes parameters, numbers and multi-character operators', () {
      final tokens = SqlSyntaxValidator.tokenize(
        'SELECT ?, ?12, :name, @v, \$x, 1.5e3, 0xFF, a <=> b, c != d',
      );
      expect(
        tokens.where((token) => token.kind == SqlTokenKind.parameter).length,
        5,
      );
      expect(
        tokens.where((token) => token.kind == SqlTokenKind.number).length,
        2,
      );
      expect(
        tokens
            .where((token) => token.kind == SqlTokenKind.operator)
            .map((token) => token.text),
        containsAll(['<=>', '!=']),
      );
    });
  });

  group('lexical diagnostics', () {
    test('accepts empty and trivia-only text', () {
      for (final text in ['', '   \r\n\t', '-- 只有注释', '/* 只有注释 */']) {
        final analysis = SqlSyntaxValidator.analyze(text);
        expect(analysis.issues, isEmpty, reason: text);
        expectBounded(analysis, text);
      }
    });

    test('reports unterminated string, identifier and block comment', () {
      // Each case is separate: an unterminated literal legitimately swallows the
      // rest of the text, so only one of them can be open at a time.
      const cases = {
        "SELECT 'abc": 'unterminated-string',
        'SELECT `x': 'unterminated-identifier',
        'SELECT "x': 'unterminated-identifier',
        'SELECT [x': 'unterminated-identifier',
        'SELECT /* open': 'unterminated-block-comment',
      };
      for (final entry in cases.entries) {
        final analysis = SqlSyntaxValidator.analyze(entry.key);
        expect(codes(analysis), [entry.value], reason: entry.key);
        expectBounded(analysis, entry.key);
        expect(analysis.issues.single.start, entry.key.indexOf(entry.key[7]));
      }
    });

    test('honors doubled quotes in every dialect', () {
      for (final text in ["SELECT 'it''s'", 'SELECT "a""b"', 'SELECT `a``b`']) {
        final analysis = SqlSyntaxValidator.analyze(text);
        expect(codes(analysis), isEmpty, reason: text);
      }
    });

    test('an escaped final quote pair does not close a token', () {
      for (final text in ["SELECT 'a''", 'SELECT "a""', 'SELECT `a``']) {
        expect(
          SqlSyntaxValidator.analyze(text).issues,
          hasLength(1),
          reason: text,
        );
      }
      expect(SqlSyntaxValidator.analyze('SELECT [closed]').issues, isEmpty);
      for (final text in ['SELECT "closed"', 'SELECT "a""b"']) {
        expect(
          SqlSyntaxValidator.analyze(text, dialect: SqlDialect.mysql).issues,
          isEmpty,
          reason: text,
        );
      }
      expect(
        codes(
          SqlSyntaxValidator.analyze('SELECT "a""', dialect: SqlDialect.mysql),
        ),
        ['unterminated-string'],
      );
    });

    test('backslash escaping depends on the dialect', () {
      // SQLite has no backslash escape: the literal closes at the backslash
      // quote, and the remaining text opens a new unterminated literal.
      const sqliteText = "SELECT 'it\\'s'";
      expect(codes(SqlSyntaxValidator.analyze(sqliteText)), [
        'unterminated-string',
      ]);
      expect(
        SqlSyntaxValidator.analyze(
          sqliteText,
          dialect: SqlDialect.mysql,
        ).issues,
        isEmpty,
      );
      expect(
        SqlSyntaxValidator.analyze(
          r"SELECT 'it\'s'",
          dialect: SqlDialect.mysql,
        ).issues,
        isEmpty,
      );
    });

    test('detects a MySQL dangling escape at the end of input', () {
      const text = r"SELECT 'abc\";
      expect(
        codes(SqlSyntaxValidator.analyze(text, dialect: SqlDialect.mysql)),
        contains('unterminated-string'),
      );
    });

    test('applies MySQL comment rules only to MySQL', () {
      // `#` comments exist in MySQL, not SQLite.
      const hash = "SELECT 1 # comment 'open";
      expect(
        SqlSyntaxValidator.analyze(hash, dialect: SqlDialect.mysql).issues,
        isEmpty,
      );
      expect(
        codes(SqlSyntaxValidator.analyze(hash)),
        contains('unterminated-string'),
      );
      // `--` requires following whitespace in MySQL.
      const dashes = "SELECT 5--'open";
      expect(codes(SqlSyntaxValidator.analyze(dashes)), isEmpty);
      expect(
        codes(SqlSyntaxValidator.analyze(dashes, dialect: SqlDialect.mysql)),
        contains('unterminated-string'),
      );
    });

    test('reports mismatched parentheses with their own offsets', () {
      const extra = 'SELECT 1)';
      final extraAnalysis = SqlSyntaxValidator.analyze(extra);
      expect(codes(extraAnalysis), ['unmatched-close-paren']);
      expect(extraAnalysis.issues.single.start, extra.indexOf(')'));

      const open = 'SELECT (1, (2';
      final openAnalysis = SqlSyntaxValidator.analyze(open);
      expect(codes(openAnalysis), [
        'unmatched-open-paren',
        'unmatched-open-paren',
      ]);
      expect(openAnalysis.issues.map((issue) => issue.start), [
        open.indexOf('('),
        open.lastIndexOf('('),
      ]);

      expect(codes(SqlSyntaxValidator.analyze('SELECT (1)')), isEmpty);
      expect(codes(SqlSyntaxValidator.analyze('SELECT (1))')), [
        'unmatched-close-paren',
      ]);
    });

    test('reports NUL characters at their exact position', () {
      const text = 'SELECT 1\x00SELECT 2';
      final analysis = SqlSyntaxValidator.analyze(text);
      expect(codes(analysis), ['nul-character']);
      expect(analysis.issues.single.start, text.indexOf('\x00'));
      expect(analysis.issues.single.severity, SqlIssueSeverity.error);
    });

    test('keeps emoji and CRLF offsets in UTF-16 code units', () {
      const text = "SELECT '😀';\r\nSELECT 'open";
      final analysis = SqlSyntaxValidator.analyze(text);
      final issue = analysis.issues.single;
      expect(issue.code, 'unterminated-string');
      expect(issue.start, text.indexOf("'open"));
      expect(issue.end, text.length);
      expect(text.substring(issue.start, issue.end), "'open");
      expectBounded(analysis, text);
    });

    test('bounds the number of reported issues', () {
      final text = List.filled(500, ')').join();
      final analysis = SqlSyntaxValidator.analyze(text);
      expect(analysis.issues.length, SqlSyntaxValidator.maxIssues);
      expectBounded(analysis, text);
    });

    test('marks a truncated scan instead of reporting clean', () {
      final text = "SELECT '${'a' * 40}";
      final analysis = SqlSyntaxValidator.analyze(text, maxUnits: 10);
      expect(analysis.truncated, isTrue);
      expect(codes(analysis), contains('scan-truncated'));
      expect(analysis.issues.last.severity, SqlIssueSeverity.information);
      expectBounded(analysis, text.substring(0, 10));
    });

    test(
      'a scan cutoff cannot prove an open token or parenthesis is invalid',
      () {
        for (final text in [
          "SELECT 'complete string';",
          'SELECT "complete identifier";',
          'SELECT `complete identifier`;',
          'SELECT [complete identifier];',
          'SELECT /* complete comment */ 1;',
          'SELECT (1234567890);',
        ]) {
          final analysis = SqlSyntaxValidator.analyze(text, maxUnits: 10);
          expect(analysis.truncated, isTrue, reason: text);
          expect(codes(analysis), ['scan-truncated'], reason: text);
        }
        // A closing parenthesis without an earlier opener is provably wrong,
        // even when scanning stops before the full input ends.
        final proven = SqlSyntaxValidator.analyze(
          'SELECT )123456',
          maxUnits: 10,
        );
        expect(codes(proven), ['unmatched-close-paren', 'scan-truncated']);
      },
    );
  });

  group('statement boundaries', () {
    List<(int, int)> ranges(String text) => [
      for (final statement in SqlSyntaxValidator.analyze(text).statements)
        (statement.start, statement.end),
    ];

    test('ignores semicolons inside literals, comments and parentheses', () {
      const text = "SELECT 'a;b'; -- c;\nSELECT (1;2); /* d; */ SELECT 3;";
      final statements = SqlSyntaxValidator.analyze(text).statements;
      expect(statements.length, 3);
      expect(statements[0].leading, 'SELECT');
      expect(
        text.substring(statements[0].start, statements[0].end),
        "SELECT 'a;b'",
      );
      expect(
        text.substring(statements[1].start, statements[1].end),
        'SELECT (1;2)',
      );
      expect(
        text.substring(statements[2].start, statements[2].end),
        'SELECT 3',
      );
    });

    test('keeps a SQLite trigger body in one statement', () {
      const text =
          'CREATE TEMP TRIGGER t AFTER INSERT ON x BEGIN '
          'UPDATE y SET a = 1; DELETE FROM z; END; SELECT 1;';
      final statements = SqlSyntaxValidator.analyze(text).statements;
      expect(statements.length, 2);
      expect(statements.first.leadingKeywords, [
        'CREATE',
        'TEMP',
        'TRIGGER',
        'T',
      ]);
      expect(
        text.substring(statements.last.start, statements.last.end),
        'SELECT 1',
      );
    });

    test('a table named trigger does not swallow later statements', () {
      const text = 'CREATE TABLE trigger (begin); SELECT 1; SELECT 2;';
      final analysis = SqlSyntaxValidator.analyze(text);
      expect(analysis.statements.map((statement) => statement.leading), [
        'CREATE',
        'SELECT',
        'SELECT',
      ]);
    });

    test('EXPLAIN prefixes preserve the complete trigger body', () {
      const body =
          'CREATE TEMP TRIGGER tr AFTER INSERT ON t BEGIN '
          'SELECT CASE WHEN 1 THEN 2 ELSE 3 END; SELECT 4; END; SELECT 5;';
      for (final prefix in ['', 'EXPLAIN ', 'EXPLAIN QUERY PLAN ']) {
        final analysis = SqlSyntaxValidator.analyze('$prefix$body');
        expect(analysis.statements, hasLength(2), reason: prefix);
        expect(
          analysis.statements.first.end,
          body.indexOf('; SELECT 5') + prefix.length,
        );
        expect(analysis.statements.last.leading, 'SELECT');
      }
    });

    test('handles CASE expressions inside a trigger body', () {
      const text =
          'CREATE TRIGGER t AFTER INSERT ON x BEGIN '
          'UPDATE y SET a = CASE WHEN a > 0 THEN 1 ELSE 0 END; END; '
          'SELECT 2;';
      expect(SqlSyntaxValidator.analyze(text).statements.length, 2);
      expect(ranges('').length, 0);
      expect(ranges('   -- only a comment  ').length, 0);
      expect(ranges('SELECT 1').length, 1);
    });

    test(
      'ambiguous trigger keyword identifiers report an informational limit',
      () {
        for (final column in ['begin', 'end']) {
          final text =
              'CREATE TRIGGER tr AFTER INSERT ON t BEGIN '
              'UPDATE t SET $column = 1; END; SELECT 1;';
          final analysis = SqlSyntaxValidator.analyze(text);
          final limit = analysis.issues.singleWhere(
            (issue) => issue.code == 'statement-boundary-unsupported',
          );
          expect(limit.severity, SqlIssueSeverity.information);
          expect(
            analysis.issues.where(
              (issue) => issue.severity == SqlIssueSeverity.error,
            ),
            isEmpty,
          );
        }
      },
    );

    test('excludes surrounding trivia from statement ranges', () {
      const text = '\n\n  SELECT 1 ;  \n';
      final statement = SqlSyntaxValidator.analyze(text).statements.single;
      expect(text.substring(statement.start, statement.end), 'SELECT 1');
    });
  });

  group('prepare guard', () {
    String target(String text) => SqlPrepareGuard.target(
      SqlSyntaxValidator.analyze(text).statements.first.leadingKeywords,
    );

    test('blocks statements whose preparation can be unsafe', () {
      for (final text in [
        'PRAGMA journal_mode = DELETE;',
        'attach database \'x.db\' as other;',
        'DETACH DATABASE other;',
        'VACUUM;',
        'REINDEX;',
        'ANALYZE;',
        'EXPLAIN PRAGMA table_info(t);',
        'EXPLAIN QUERY PLAN PRAGMA table_info(t);',
      ]) {
        final statement = SqlSyntaxValidator.analyze(text).statements.single;
        expect(
          SqlPrepareGuard.blockedReason(statement),
          isNotNull,
          reason: text,
        );
      }
    });

    test('allows ordinary queries, DML and DDL', () {
      for (final text in [
        'SELECT * FROM t;',
        'INSERT INTO t VALUES (1);',
        'UPDATE t SET a = 1;',
        'DELETE FROM t;',
        'CREATE TABLE t (a INTEGER);',
        'DROP TABLE t;',
        'WITH c AS (SELECT 1) SELECT * FROM c;',
        'EXPLAIN QUERY PLAN SELECT 1;',
      ]) {
        final statement = SqlSyntaxValidator.analyze(text).statements.single;
        expect(SqlPrepareGuard.blockedReason(statement), isNull, reason: text);
      }
    });

    test('reports the guarded keyword itself', () {
      expect(target('PRAGMA table_info(t)'), 'PRAGMA');
      expect(target('EXPLAIN QUERY PLAN PRAGMA table_info(t)'), 'PRAGMA');
      expect(target('select 1'), 'SELECT');
      expect(SqlPrepareGuard.target(const []), '');
    });
  });
}
