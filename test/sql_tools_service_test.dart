import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_execution_context.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_tools_service.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_sql/sqlite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('statement splitting', () {
    test('ignores separators inside literals, identifiers and comments', () {
      const source = '''
SELECT ';' AS a; -- trailing ; comment
INSERT INTO "semi;table" VALUES (1, 'x;y');
/* block ; comment */
SELECT 3
''';
      expect(countSqlStatements(source), 3);
      expect(splitSqlStatements(source).first, "SELECT ';' AS a");
    });

    test('doubled quotes and CRLF survive unchanged', () {
      const source = "SELECT 'it''s ; fine';\r\nSELECT 2";
      final statements = splitSqlStatements(source);
      expect(statements, hasLength(2));
      expect(statements.first, "SELECT 'it''s ; fine'");
      expect(statements.last, 'SELECT 2');
    });

    test('comments-only and empty input have no statements', () {
      expect(countSqlStatements(''), 0);
      expect(countSqlStatements('  -- only a comment\n'), 0);
    });

    test('does not guess ambiguous trigger boundaries', () {
      const source =
          'CREATE TRIGGER t AFTER INSERT ON x BEGIN '
          'UPDATE x SET end=1; END; SELECT 2;';
      expect(
        () => countSqlStatements(source),
        throwsA(isA<SqlToolsException>()),
      );
    });
  });

  group('shared dialect-aware scanner reuse', () {
    test('MySQL requires whitespace after -- so 1--2 is arithmetic', () {
      // The shared scanner must not treat `--2` as a comment in MySQL.
      expect(
        splitSqlStatements('SELECT 1--2; SELECT 3', dialect: SqlDialect.mysql),
        ['SELECT 1--2', 'SELECT 3'],
      );
      expect(
        splitSqlStatements('SELECT 1--2', dialect: SqlDialect.mysql).single,
        'SELECT 1--2',
      );
      // SQLite does treat it as a comment, so the rest of the line is trivia.
      expect(
        countSqlStatements('SELECT 1--2; SELECT 3', dialect: SqlDialect.sqlite),
        1,
      );
    });

    test('MySQL -- with whitespace comments out a separator', () {
      const source = 'SELECT 1 -- ; not a separator\n; SELECT 2';
      // Statement ranges come from the shared splitter and exclude trailing
      // trivia, so the comment text is not part of either statement.
      expect(splitSqlStatements(source, dialect: SqlDialect.mysql), [
        'SELECT 1',
        'SELECT 2',
      ]);
      expect(
        countSqlStatements('SELECT 1 -- ;\n', dialect: SqlDialect.mysql),
        1,
      );
      expect(
        countSqlStatements(
          'SELECT 1 -- ;\n; SELECT 2',
          dialect: SqlDialect.mysql,
        ),
        2,
      );
    });

    test('SQLite backslash is literal while MySQL treats it as an escape', () {
      const source = r"SELECT '\'; SELECT 2";
      // SQLite: '\' is a terminated string, so two statements exist.
      expect(
        splitSqlStatements(source, dialect: SqlDialect.sqlite),
        hasLength(2),
      );
      // MySQL: the closing quote is escaped, so the whole tail is one string.
      expect(
        splitSqlStatements(source, dialect: SqlDialect.mysql),
        hasLength(1),
      );
    });

    test(
      'semicolons inside literals, comments and routine bodies never split',
      () {
        expect(countSqlStatements("SELECT 'a;b'; -- c;d\nSELECT 2"), 2);
        expect(countSqlStatements('/* ; */ SELECT 1'), 1);
        // A MySQL escaped-quote string keeps its embedded separator.
        expect(
          splitSqlStatements(
            r"SELECT 'a\'; SELECT 2';",
            dialect: SqlDialect.mysql,
          ),
          hasLength(1),
        );
      },
    );

    test('formatter preserves dialect literals beyond command starts', () {
      // MySQL: `1--2` is arithmetic, so the `--2` must not be kept as comment
      // text and the statement must still be formatted.
      expect(
        formatSqlText('select 1--2', dialect: SqlDialect.mysql),
        'SELECT 1--2',
      );
      // SQLite: `--2` is a comment and must be copied byte-for-byte.
      expect(
        formatSqlText('select 1--2', dialect: SqlDialect.sqlite),
        'SELECT 1--2',
      );
      expect(
        formatSqlText(
          "select 'from where' as \"select\" # note",
          dialect: SqlDialect.mysql,
        ),
        "SELECT 'from where' as \"select\" # note",
      );
      expect(
        formatSqlText(r"select 'a\b' from t", dialect: SqlDialect.mysql),
        r"SELECT 'a\b' from t",
      );
      expect(
        formatSqlText(r"select 'a\b' from t", dialect: SqlDialect.sqlite),
        r"SELECT 'a\b' from t",
      );
    });

    test('plan guard uses shared statement boundaries, not naive split', () {
      // The `;` lives inside a MySQL escaped string, so this is one statement.
      expect(
        buildSqlPlanRequest(r"SELECT 'a\';b'", SqlDialect.mysql),
        r"EXPLAIN SELECT 'a\';b'",
      );
      expect(
        () => buildSqlPlanRequest('SELECT 1; SELECT 2', SqlDialect.mysql),
        throwsA(isA<SqlToolsException>()),
      );
      for (final source in [
        "SELECT * FROM t INTO OUTFILE '/tmp/x'",
        'EXPLAIN ANALYZE SELECT 1',
        'ANALYZE TABLE t',
      ]) {
        expect(
          () => buildSqlPlanRequest(source, SqlDialect.mysql),
          throwsA(isA<SqlToolsException>()),
          reason: source,
        );
      }
    });
  });

  group('formatSqlText', () {
    test('normalizes command starts and preserves the statement body', () {
      const source =
          "select \"MiXeD\" as name, 'select * from t' -- keep Me\nfrom t;";
      final formatted = formatSqlText(source);
      expect(formatted, startsWith('SELECT "MiXeD" as name'));
      expect(formatted, contains("'select * from t'"));
      expect(formatted, contains('-- keep Me'));
      expect(formatted, endsWith('from t;'));
    });

    test(
      'preserves MySQL identifier and alias case for keyword-like names',
      () {
        const source =
            'select real as text, text.real, null as real from text as real; '
            'select text from real; update text set real = 1;';
        expect(
          formatSqlText(source, dialect: SqlDialect.mysql),
          'SELECT real as text, text.real, null as real from text as real; '
          'SELECT text from real; UPDATE text set real = 1;',
        );
      },
    );

    test('keeps quoted content, comments and separators verbatim', () {
      const source =
          "/* select; */ select `text`, 'real; select' as \"MiXeD\" from real;"
          "\r\n# select text\r\nselect 2; -- final comment";
      expect(
        formatSqlText(source, dialect: SqlDialect.mysql),
        "/* select; */ SELECT `text`, 'real; select' as \"MiXeD\" from real;"
        "\r\n# select text\r\nSELECT 2; -- final comment",
      );
    });

    test(
      'preserves source when lexical boundaries are incomplete or ambiguous',
      () {
        for (final source in [
          "select 'open",
          'create trigger tr after insert on t begin update t set end = 1; end;',
        ]) {
          expect(formatSqlText('  $source  '), source);
        }
      },
    );

    test('does not append a separator after a trailing line comment', () {
      const source = 'select 1 -- note';
      final formatted = formatSqlText(source);
      expect(formatted, 'SELECT 1 -- note');
      expect(formatted.endsWith(';'), isFalse);
    });

    test('keeps unknown tokens and empty input intact', () {
      expect(formatSqlText(''), '');
      expect(formatSqlText('select myFunc(1)'), 'SELECT myFunc(1)');
    });
  });

  group('identifier and value helpers', () {
    test('quotes identifiers per dialect', () {
      expect(quoteSqlIdentifier('plain', SqlDialect.sqlite), '"plain"');
      expect(quoteSqlIdentifier('we"ird', SqlDialect.sqlite), '"we""ird"');
      expect(quoteSqlIdentifier('plain', SqlDialect.mysql), '`plain`');
      expect(
        () => quoteSqlIdentifier('back`tick', SqlDialect.mysql),
        throwsA(isA<SqlToolsException>()),
      );
      expect(
        () => quoteSqlIdentifier(' padded ', SqlDialect.sqlite),
        throwsA(isA<SqlToolsException>()),
      );
      expect(
        () => quoteSqlIdentifier('', SqlDialect.sqlite),
        throwsA(isA<SqlToolsException>()),
      );
    });

    test('escapes string literals and refuses NUL', () {
      expect(quoteSqlString("it's", SqlDialect.sqlite), "'it''s'");
      expect(quoteSqlString(r'a\b', SqlDialect.mysql), r"'a\\b'");
      expect(quoteSqlString("it's", SqlDialect.mysql), "'it''s'");
      expect(
        () => quoteSqlString('bad\u0000', SqlDialect.sqlite),
        throwsA(isA<SqlToolsException>()),
      );
      expect(sqlNullLiteral, 'NULL');
    });

    test('NULL and empty string stay distinct', () {
      expect(describeSqlCell(null), 'SQL NULL');
      expect(describeSqlCell(''), contains('空字符串'));
      expect(describeSqlCell('abc'), contains('3'));
    });
  });

  group('sqlResultToCsv', () {
    test('distinguishes NULL from empty string and quotes fields', () {
      final csv = sqlResultToCsv(
        ['id', 'note'],
        [
          ['1', null],
          ['2', ''],
          ['3', 'a,b'],
          ['4', 'say "hi"'],
          ['5', 'line\nbreak'],
        ],
      );
      final lines = csv.split('\r\n');
      expect(lines.first, 'id,note');
      expect(lines[1], '1,');
      expect(lines[2], '2,""');
      expect(lines[3], '3,"a,b"');
      expect(lines[4], '4,"say ""hi"""');
      expect(csv, contains('"line\nbreak"'));
    });
  });

  group('buildSqlPlanRequest', () {
    test(
      'rejects incomplete scans and lexical errors before plan dispatch',
      () {
        for (final source in [
          "SELECT 'unterminated",
          'SELECT (1',
          'SELECT 1 /* open comment',
          'SELECT 1 ${' ' * (1024 * 1024)}; DELETE FROM t',
        ]) {
          expect(
            () => buildSqlPlanRequest(source, SqlDialect.mysql),
            throwsA(isA<SqlToolsException>()),
          );
        }
      },
    );

    test('token guard sees file writes across comments and newlines', () {
      for (final source in [
        "SELECT * FROM t INTO/**/OUTFILE '/tmp/x'",
        "SELECT * FROM t INTO\nDUMPFILE '/tmp/x'",
        "SELECT 1 /*! INTO OUTFILE '/tmp/x' */",
        'SELECT 1 /*!; ANALYZE TABLE t */',
        '/*!80000 SELECT 1 */',
        'WITH x AS (SELECT 1) DELETE FROM t',
      ]) {
        expect(
          () => buildSqlPlanRequest(source, SqlDialect.mysql),
          throwsA(isA<SqlToolsException>()),
          reason: source,
        );
      }
      expect(
        buildSqlPlanRequest(
          "SELECT 'INTO OUTFILE', 'ANALYZE'",
          SqlDialect.mysql,
        ),
        "EXPLAIN SELECT 'INTO OUTFILE', 'ANALYZE'",
      );
      expect(
        buildSqlPlanRequest('/* ordinary */ SELECT 1', SqlDialect.mysql),
        'EXPLAIN SELECT 1',
      );
      expect(
        buildSqlPlanRequest(
          'WITH x AS (SELECT 1), y AS (SELECT * FROM x) SELECT * FROM y',
          SqlDialect.sqlite,
        ),
        startsWith('EXPLAIN QUERY PLAN WITH'),
      );
    });
    test('uses the non-executing plan form for each dialect', () {
      expect(
        buildSqlPlanRequest('SELECT 1;', SqlDialect.sqlite),
        'EXPLAIN QUERY PLAN SELECT 1',
      );
      expect(
        buildSqlPlanRequest('select * from t', SqlDialect.mysql),
        'EXPLAIN select * from t',
      );
      expect(
        buildSqlPlanRequest(
          'WITH x AS (SELECT 1) SELECT * FROM x',
          SqlDialect.sqlite,
        ),
        startsWith('EXPLAIN QUERY PLAN WITH x'),
      );
    });

    test('refuses forms that could execute or mutate', () {
      for (final source in [
        'EXPLAIN ANALYZE SELECT 1',
        'ANALYZE',
        'ANALYZE TABLE t',
        'DELETE FROM t',
        'INSERT INTO t VALUES (1)',
        'PRAGMA writable_schema = 1',
        'SELECT 1; SELECT 2',
        '',
      ]) {
        expect(
          () => buildSqlPlanRequest(source, SqlDialect.sqlite),
          throwsA(isA<SqlToolsException>()),
          reason: source,
        );
      }
    });

    test('rejects MySQL-only unsupported plan forms', () {
      expect(
        () => buildSqlPlanRequest('VALUES (1)', SqlDialect.mysql),
        throwsA(isA<SqlToolsException>()),
      );
    });
  });

  group('SqlToolsController', () {
    late _FakeRepository repository;
    late _FakeLibrary library;

    SqlToolsController controller({
      SqlEngineKind engine = SqlEngineKind.localMysql,
      bool withLibrary = true,
      _FakeLibrary? libraryOverride,
    }) {
      final fakeLibrary = libraryOverride ?? library;
      return SqlToolsController(
        openTarget: () async => SqlExecutionContext.forTesting(
          engine: engine,
          repository: repository,
        ),
        openLibrary: () async => fakeLibrary,
        libraryEnabled: withLibrary,
        watchPreference: false,
      );
    }

    setUp(() {
      repository = _FakeRepository();
      library = _FakeLibrary();
    });

    test(
      'initializes real context and schema through the repository',
      () async {
        final subject = controller();
        await subject.initialize();

        expect(subject.engineLabel, '本机 MySQL');
        expect(subject.dialect, SqlDialect.mysql);
        expect(subject.databases, ['shop']);
        expect(subject.database, 'shop');
        expect(subject.tables, ['items']);
        expect(subject.table, 'items');
        expect(subject.columns.map((column) => column.name), ['id', 'name']);
        expect(subject.indexes.map((index) => index.name), [
          'PRIMARY',
          'items_name',
        ]);
        expect(subject.schemaNote, isNull);
        expect(subject.canExecute, isTrue);
        expect(repository.tableColumnsCalls, isNotEmpty);
        subject.dispose();
      },
    );

    test(
      'runs the retained source on the selected database and keeps all results',
      () async {
        final subject = controller();
        await subject.initialize();
        subject.source = 'SELECT 1; SELECT 2;';
        await subject.runScript();

        expect(repository.scriptCalls.single.$1, 'shop');
        expect(repository.scriptCalls.single.$2, 'SELECT 1; SELECT 2;');
        expect(subject.script!.results, hasLength(2));
        expect(subject.script!.results[1].rows.single.single, '2');
        expect(subject.script!.truncated, isTrue);
        expect(subject.executionError, isNull);
        expect(library.history.single.success, isTrue);
        subject.dispose();
      },
    );

    test(
      'exposes SQLSTATE and partial failure without dropping prior results',
      () async {
        final subject = controller();
        await subject.initialize();
        repository.scriptResult = SqlScriptResult(
          summary: SqlQueryResult(
            available: true,
            exitCode: 1,
            columns: const [],
            rows: const [],
            affectedRows: 0,
            truncated: false,
            error: 'Table does not exist',
            sqlState: '42S02',
          ),
          results: [
            const SqlQueryResult(
              available: true,
              exitCode: 0,
              columns: ['n'],
              rows: [
                ['1'],
              ],
              affectedRows: 0,
              truncated: false,
            ),
          ],
        );
        subject.source = 'SELECT 1; SELECT * FROM missing;';
        await subject.runScript();

        expect(subject.script!.success, isFalse);
        expect(subject.script!.results, hasLength(1));
        expect(subject.script!.summary.sqlState, '42S02');
        expect(subject.script!.summary.exitCode, 1);
        expect(library.history.single.success, isFalse);
        subject.dispose();
      },
    );

    test('keeps the SQL result when history persistence fails', () async {
      final failing = _FakeLibrary(failOnRecord: true);
      final subject = controller(libraryOverride: failing);
      await subject.initialize();
      subject.source = 'SELECT 1';
      await subject.runScript();

      expect(subject.script, isNotNull);
      expect(subject.script!.results, isNotEmpty);
      expect(subject.libraryError, contains('磁盘写入失败'));
      subject.dispose();
    });

    test(
      'reports an unavailable engine as an error, not a clean result',
      () async {
        final subject = SqlToolsController(
          openTarget: () async => throw const FileSystemException('无法访问应用数据目录'),
          openLibrary: () async => library,
        );
        await subject.initialize();

        expect(subject.target, isNull);
        expect(subject.canExecute, isFalse);
        expect(subject.contextError, contains('无法访问应用数据目录'));
        subject.dispose();
      },
    );

    test(
      'explain runs only the plan query and never the source statement',
      () async {
        final subject = controller();
        await subject.initialize();
        subject.source = 'SELECT * FROM items';
        await subject.explain();

        expect(repository.queryCalls.single.$1, 'shop');
        expect(repository.queryCalls.single.$2, 'EXPLAIN SELECT * FROM items');
        expect(repository.scriptCalls, isEmpty);
        expect(subject.plan!.planSql, 'EXPLAIN SELECT * FROM items');
        expect(subject.plan!.engineLabel, '本机 MySQL');
        expect(subject.plan!.result.columns, ['id', 'select_type']);
        subject.dispose();
      },
    );

    test('refuses to explain a mutating or ANALYZE statement', () async {
      final subject = controller();
      await subject.initialize();
      subject.source = 'EXPLAIN ANALYZE SELECT 1';
      await subject.explain();

      expect(subject.plan, isNull);
      expect(subject.executionError, contains('EXPLAIN ANALYZE'));
      expect(repository.queryCalls, isEmpty);
      subject.dispose();
    });

    test('serializes commands and refuses to start a second run', () async {
      final subject = controller();
      await subject.initialize();
      final gate = repository.blockScripts();
      subject.source = 'SELECT 1';
      final first = subject.runScript();
      await Future<void>.delayed(Duration.zero);
      expect(subject.busy, isTrue);
      await subject.runScript();
      gate.complete();
      await first;

      expect(repository.scriptCalls, hasLength(1));
      expect(subject.busy, isFalse);
      subject.dispose();
    });

    test(
      'SQLite inspects indexes independently of mutation capabilities',
      () async {
        repository.indexesUnsupported = true;
        final subject = controller(engine: SqlEngineKind.sqlite);
        await subject.initialize();

        expect(subject.dialect, SqlDialect.sqlite);
        final index = subject.indexes.single as SqliteToolIndex;
        expect(index.name, 'items_name');
        expect(index.columns, ['name']);
        expect(index.partial, isTrue);
        expect(subject.schemaNote, isNull);
        expect(repository.queryCalls.map((call) => call.$2), [
          "PRAGMA main.index_list('items')",
          "PRAGMA main.index_info('items_name')",
        ]);
        expect(subject.supportsSchemaTools, isFalse);
        expect(
          () => subject.buildCreateIndexSql(
            name: 'idx',
            columns: ['name'],
            unique: false,
          ),
          throwsA(isA<SqlToolsException>()),
        );
        subject.dispose();
      },
    );

    for (final failure in [
      SqlQueryResult.unavailable('索引引擎不可用'),
      const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: ['name', 'unique', 'origin', 'partial'],
        rows: [],
        affectedRows: 0,
        truncated: true,
      ),
      const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: ['unexpected'],
        rows: [],
        affectedRows: 0,
        truncated: false,
      ),
    ]) {
      test(
        'SQLite reports unavailable, truncated or malformed index metadata ${failure.error ?? failure.columns}',
        () async {
          repository.sqliteIndexList = failure;
          final subject = controller(engine: SqlEngineKind.sqlite);
          addTearDown(subject.dispose);
          await subject.initialize();
          expect(subject.columns, hasLength(2));
          expect(subject.indexes, isEmpty);
          expect(subject.schemaNote, isNotEmpty);
          expect(repository.queryCalls, hasLength(1));
        },
      );
    }

    test('builds quoted index statements without executing them', () async {
      final subject = controller();
      await subject.initialize();
      final create = subject.buildCreateIndexSql(
        name: 'idx name',
        columns: ['name', 'id'],
        unique: true,
      );
      expect(
        create,
        'CREATE UNIQUE INDEX `idx name` ON `items` (`name`, `id`);',
      );
      expect(
        subject.buildDropIndexSql('items_name'),
        'DROP INDEX `items_name` ON `items`;',
      );
      expect(repository.scriptCalls, isEmpty);
      expect(repository.queryCalls, isEmpty);
      subject.dispose();
    });

    test('does not re-run a command while busy', () async {
      final subject = controller();
      await subject.initialize();
      final gate = repository.blockScripts();
      subject.source = 'SELECT 1';
      final pending = subject.runScript();
      await Future<void>.delayed(Duration.zero);
      await subject.explain();
      gate.complete();
      await pending;
      expect(repository.queryCalls, isEmpty);
      subject.dispose();
    });

    for (final stage in [
      'databases',
      'tables',
      'columns',
      'indexes',
      'index columns',
    ]) {
      test(
        'engine change discards late $stage and stops old metadata dispatch',
        () async {
          final changes = ValueNotifier(0);
          final previous = _DeferredRepository('old')..pauseAt = stage;
          final next = _DeferredRepository('next');
          var oldCurrent = true;
          var opens = 0;
          final subject = SqlToolsController(
            engineChanges: changes,
            libraryEnabled: false,
            openTarget: () async => ++opens == 1
                ? SqlExecutionContext.forTesting(
                    engine: SqlEngineKind.sqlite,
                    repository: previous,
                    isCurrent: () => oldCurrent,
                  )
                : SqlExecutionContext.forTesting(
                    engine: SqlEngineKind.localMysql,
                    repository: next,
                  ),
          );
          addTearDown(changes.dispose);
          addTearDown(subject.dispose);
          final published = <String>[];
          subject.addListener(
            () => published.add(
              [
                ...subject.databases,
                ...subject.tables,
                ...subject.columns.map((column) => column.name),
                ...subject.indexes.map((index) => index.name),
              ].join('|'),
            ),
          );
          final initializing = subject.initialize();
          await previous.entered.future;

          oldCurrent = false;
          changes.value++;
          published.clear();
          expect(subject.initializing, isTrue);
          expect(subject.target, isNull);
          subject.source = 'SELECT retained;';
          await subject.runScript();
          expect(opens, 1, reason: 'old initialization still owns its lock');
          previous.release.complete();
          await initializing;
          await Future<void>.delayed(Duration.zero);

          expect(subject.engineLabel, '本机 MySQL');
          expect(subject.databases, ['next-db']);
          expect(subject.tables, ['next-table']);
          expect(subject.columns.single.name, 'next-column');
          expect(subject.indexes.single.name, 'next-index');
          expect(subject.source, 'SELECT retained;');
          expect(
            published.any((snapshot) => snapshot.contains('old-')),
            isFalse,
          );
          expect(
            previous.calls.last,
            stage,
            reason: 'no further command may use the invalidated engine',
          );
          expect(previous.scriptCalls, isEmpty);
          expect(next.scriptCalls, isEmpty);
        },
      );
    }

    for (final planning in [false, true]) {
      test(
        'engine change keeps ${planning ? 'plan' : 'script'} lock until native settles',
        () async {
          final changes = ValueNotifier(0);
          final previous = _DeferredRepository('old');
          final next = _DeferredRepository('next');
          var opens = 0;
          final subject = SqlToolsController(
            engineChanges: changes,
            openLibrary: () async => library,
            openTarget: () async => SqlExecutionContext.forTesting(
              engine: opens++ == 0
                  ? SqlEngineKind.sqlite
                  : SqlEngineKind.localMysql,
              repository: opens == 1 ? previous : next,
            ),
          );
          addTearDown(changes.dispose);
          addTearDown(subject.dispose);
          await subject.initialize();
          previous.pauseAt = planning ? 'query' : 'script';
          subject.source = 'SELECT 7';
          final pending = planning ? subject.explain() : subject.runScript();
          await previous.entered.future;
          changes.value++;
          expect(subject.busy, isTrue);
          expect(subject.target, isNull);
          await subject.runScript();
          await subject.explain();
          expect(opens, 1);
          expect(next.calls, isEmpty);
          final stalePublications = <bool>[];
          subject.addListener(
            () => stalePublications.add(
              subject.script != null || subject.plan != null,
            ),
          );
          previous.release.complete();
          await pending;
          await Future<void>.delayed(Duration.zero);

          expect(subject.busy, isFalse);
          expect(subject.engineLabel, '本机 MySQL');
          expect(stalePublications, everyElement(isFalse));
          expect(
            library.history,
            isEmpty,
            reason: 'an invalidated execution cannot write history afterward',
          );
          expect(next.scriptCalls, isEmpty);
          await subject.runScript();
          expect(next.scriptCalls.single, ('next-db', 'SELECT 7'));
        },
      );
    }

    test(
      'late history failure cannot replace the new engine storage state',
      () async {
        final changes = ValueNotifier(0);
        final history = _DelayedLibrary();
        var opens = 0;
        final subject = SqlToolsController(
          engineChanges: changes,
          openTarget: () async => SqlExecutionContext.forTesting(
            engine: opens++ == 0
                ? SqlEngineKind.sqlite
                : SqlEngineKind.localMysql,
            repository: repository,
          ),
          openLibrary: () async => history,
        );
        addTearDown(changes.dispose);
        addTearDown(subject.dispose);
        await subject.initialize();
        subject.source = 'SELECT 1';
        final pending = subject.runScript();
        await history.entered.future;
        changes.value++;
        expect(subject.busy, isTrue);
        history.release.complete();
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(subject.engineLabel, '本机 MySQL');
        expect(subject.script, isNull);
        expect(subject.libraryError, isNull);
        expect(subject.library, same(history));
      },
    );

    test(
      'late library opening error does not publish into new context',
      () async {
        final changes = ValueNotifier(0);
        final delayed = Completer<SqlQueryLibrary>();
        final entered = Completer<void>();
        var libraryOpens = 0;
        final subject = SqlToolsController(
          engineChanges: changes,
          openTarget: () async => SqlExecutionContext.forTesting(
            engine: SqlEngineKind.sqlite,
            repository: repository,
          ),
          openLibrary: () {
            if (libraryOpens++ > 0) return Future.value(library);
            entered.complete();
            return delayed.future;
          },
        );
        addTearDown(changes.dispose);
        addTearDown(subject.dispose);
        final pending = subject.initialize();
        await entered.future;
        changes.value++;
        delayed.completeError(
          const FileSystemException('previous storage error'),
        );
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(subject.library, same(library));
        expect(subject.libraryError, isNull);
        expect(subject.initializing, isFalse);
      },
    );

    test(
      'stale context cannot dispatch even before a change notification',
      () async {
        var current = true;
        var opens = 0;
        final subject = SqlToolsController(
          watchPreference: false,
          libraryEnabled: false,
          openTarget: () async => SqlExecutionContext.forTesting(
            engine: SqlEngineKind.sqlite,
            repository: repository,
            isCurrent: opens++ == 0 ? () => current : () => true,
          ),
        );
        addTearDown(subject.dispose);
        await subject.initialize();
        current = false;
        subject.source = 'DELETE FROM items';
        await subject.runScript();
        await Future<void>.delayed(Duration.zero);
        expect(repository.scriptCalls, isEmpty);
        expect(subject.canExecute, isTrue);
        expect(opens, 2);
      },
    );
  });

  final nativeLibrary =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(
        Directory.current.path,
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
      );
  test(
    'command normalization preserves a real SQLite text table and result headers',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'qfli_tools_formatter_',
      );
      addTearDown(() => root.delete(recursive: true));
      final database = _BundledSqlite(nativeLibrary);
      final databasePath = p.join(root.path, 'formatter.sqlite');
      final fixture = await database.executeScript(
        databasePath: databasePath,
        source:
            'CREATE TABLE text (real TEXT, text TEXT); '
            "INSERT INTO text VALUES ('kept', 'value');",
      );
      expect(fixture.success, isTrue, reason: fixture.error);
      const source =
          "select real, text, null, 1 in (1), 2 between 1 and 3, "
          "4 as text, 5 real, 'keep; select text' as \"Quoted\" from text;";
      final before = await database.query(
        databasePath: databasePath,
        source: source,
      );
      final after = await database.query(
        databasePath: databasePath,
        source: formatSqlText(source),
      );
      expect(before.exitCode, 0, reason: before.error);
      expect(after.exitCode, 0, reason: after.error);
      expect(before.columns, [
        'real',
        'text',
        'null',
        '1 in (1)',
        '2 between 1 and 3',
        'text',
        'real',
        'Quoted',
      ]);
      expect(after.columns, before.columns);
      expect(after.rows, before.rows);
      expect(after.rows.single.take(2), ['kept', 'value']);
    },
    skip: !File(nativeLibrary).existsSync()
        ? 'Bundled SQLite library missing: $nativeLibrary'
        : false,
  );
  test(
    'bundled SQLite preserves real index metadata and plans without executing queries',
    () async {
      final root = await Directory.systemTemp.createTemp('qfli_tools_index_');
      addTearDown(() => root.delete(recursive: true));
      final database = _BundledSqlite(nativeLibrary);
      final repository = SqlWorkspaceRepository(
        root: root,
        database: database,
        scriptDatabase: database,
      );
      await repository.createDatabase('inspection');
      const table = "owner's items";
      final quoted = quoteSqlIdentifier(table, SqlDialect.sqlite);
      const normalName = "idx ' quote; --";
      final fixture = await repository.runScript('inspection', '''
CREATE TABLE $quoted (a TEXT PRIMARY KEY, b TEXT UNIQUE, c INTEGER);
INSERT INTO $quoted VALUES ('key', 'Ada', 3);
CREATE INDEX ${quoteSqlIdentifier(normalName, SqlDialect.sqlite)} ON $quoted(c, b);
CREATE INDEX "partial index" ON $quoted(c) WHERE c > 0;
CREATE INDEX "expression index" ON $quoted(lower(b));
''');
      expect(fixture.success, isTrue, reason: fixture.error);
      final before = await repository.runQuery(
        'inspection',
        'SELECT * FROM $quoted',
      );
      final subject = SqlToolsController(
        openTarget: () async => SqlExecutionContext.forTesting(
          engine: SqlEngineKind.sqlite,
          repository: repository,
        ),
        watchPreference: false,
        libraryEnabled: false,
      );
      addTearDown(subject.dispose);
      await subject.initialize();
      expect(subject.schemaNote, isNull);
      expect(subject.schemaError, isNull);
      final indexes = {
        for (final index in subject.indexes.cast<SqliteToolIndex>())
          index.name: index,
      };
      expect(indexes, hasLength(5));
      expect(indexes[normalName]!.columns, ['c', 'b']);
      expect(indexes['partial index']!.partial, isTrue);
      expect(indexes['expression index']!.columns, ['（表达式）']);
      expect(indexes.values.where((index) => index.primary).single.columns, [
        'a',
      ]);
      final automatic = indexes.values.where((index) => index.automatic);
      expect(automatic, hasLength(2));
      expect(
        automatic.every(
          (index) => index.unique && index.name.startsWith('sqlite_autoindex_'),
        ),
        isTrue,
      );
      expect(automatic.singleWhere((index) => index.origin == 'u').columns, [
        'b',
      ]);
      expect(subject.supportsSchemaTools, isFalse);
      subject.source = "SELECT b FROM $quoted WHERE c = 3";
      await subject.explain();
      expect(
        subject.plan!.result.success,
        isTrue,
        reason: subject.plan!.result.error,
      );
      expect(subject.plan!.result.rows, isNotEmpty);
      expect(
        (await repository.runQuery('inspection', 'SELECT * FROM $quoted')).rows,
        before.rows,
      );
      expect(
        (await repository.runQuery(
          'inspection',
          'PRAGMA integrity_check',
        )).rows,
        [
          ['ok'],
        ],
      );
      // A successful DROP of the last table must remove its cached structure.
      subject.source = 'DROP TABLE $quoted;';
      await subject.runScript();
      expect(subject.script!.success, isTrue, reason: subject.script!.error);
      expect(subject.tables, isEmpty);
      expect(subject.table, isNull);
      expect(subject.columns, isEmpty);
      expect(subject.indexes, isEmpty);
      expect(subject.schemaError, isNull);
      expect(subject.schemaNote, isNull);
      expect(await repository.listTables('inspection'), isEmpty);
    },
    skip: !File(nativeLibrary).existsSync()
        ? 'Bundled SQLite library missing: $nativeLibrary'
        : false,
  );
}

class _DeferredRepository extends _FakeRepository {
  _DeferredRepository(this.label);
  final String label;
  String? pauseAt;
  final entered = Completer<void>();
  final release = Completer<void>();
  final calls = <String>[];
  bool _held = false;

  Future<void> _wait(String operation) async {
    calls.add(operation);
    if (!_held && operation == pauseAt) {
      _held = true;
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<List<String>> listDatabases() async {
    await _wait('databases');
    return ['$label-db'];
  }

  @override
  Future<List<String>> listTables(String databaseName) async {
    await _wait('tables');
    return ['$label-table'];
  }

  @override
  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async {
    await _wait('columns');
    return [
      SqlColumn(
        name: '$label-column',
        type: 'TEXT',
        notNull: false,
        primaryKey: false,
      ),
    ];
  }

  @override
  Future<List<SqlIndex>> tableIndexes(String databaseName, String table) async {
    await _wait('indexes');
    return [
      SqlIndex(name: '$label-index', columns: ['$label-column'], unique: false),
    ];
  }

  @override
  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    await _wait('script');
    return super.runScript(databaseName, source);
  }

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) async {
    if (source.startsWith('PRAGMA main.index_list(')) {
      await _wait('indexes');
    } else if (source.startsWith('PRAGMA main.index_info(')) {
      await _wait('index columns');
    } else {
      await _wait('query');
    }
    return super.runQuery(databaseName, source);
  }
}

class _DelayedLibrary extends _FakeLibrary {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {
    entered.complete();
    await release.future;
    throw const FileSystemException('old history failed');
  }
}

class _FakeRepository extends SqlWorkspaceRepository {
  _FakeRepository() : super(root: Directory.systemTemp);

  final List<(String, String)> scriptCalls = [];
  final List<(String, String)> queryCalls = [];
  final List<String> tableColumnsCalls = [];
  bool indexesUnsupported = false;
  SqlQueryResult? sqliteIndexList;
  SqlScriptResult? scriptResult;
  Completer<void>? _gate;

  Completer<void> blockScripts() => _gate = Completer<void>();

  @override
  bool get supportsSchemaTools => !indexesUnsupported;

  @override
  Future<List<String>> listDatabases() async => ['shop'];

  @override
  Future<List<String>> listTables(String databaseName) async => ['items'];

  @override
  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async {
    tableColumnsCalls.add('$databaseName.$table');
    return const [
      SqlColumn(name: 'id', type: 'INTEGER', notNull: true, primaryKey: true),
      SqlColumn(name: 'name', type: 'TEXT', notNull: false, primaryKey: false),
    ];
  }

  @override
  Future<List<SqlIndex>> tableIndexes(String databaseName, String table) async {
    if (indexesUnsupported) {
      throw UnsupportedError('当前数据库引擎不支持索引操作');
    }
    return const [
      SqlIndex(name: 'PRIMARY', columns: ['id'], unique: true, primary: true),
      SqlIndex(name: 'items_name', columns: ['name'], unique: false),
    ];
  }

  @override
  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    scriptCalls.add((databaseName, source));
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      await gate.future;
    }
    return scriptResult ??
        SqlScriptResult(
          summary: const SqlQueryResult(
            available: true,
            exitCode: 0,
            columns: ['n'],
            rows: [
              ['1'],
              ['2'],
            ],
            affectedRows: 0,
            truncated: true,
          ),
          results: const [
            SqlQueryResult(
              available: true,
              exitCode: 0,
              columns: ['n'],
              rows: [
                ['1'],
              ],
              affectedRows: 0,
              truncated: false,
            ),
            SqlQueryResult(
              available: true,
              exitCode: 0,
              columns: ['n'],
              rows: [
                ['2'],
              ],
              affectedRows: 0,
              truncated: false,
            ),
          ],
        );
  }

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) async {
    queryCalls.add((databaseName, source));
    if (source.startsWith('PRAGMA main.index_list(')) {
      return sqliteIndexList ??
          const SqlQueryResult(
            available: true,
            exitCode: 0,
            columns: ['seq', 'name', 'unique', 'origin', 'partial'],
            rows: [
              ['0', 'items_name', '0', 'c', '1'],
            ],
            affectedRows: 0,
            truncated: false,
          );
    }
    if (source.startsWith('PRAGMA main.index_info(')) {
      return const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: ['seqno', 'cid', 'name'],
        rows: [
          ['0', '1', 'name'],
        ],
        affectedRows: 0,
        truncated: false,
      );
    }
    return const SqlQueryResult(
      available: true,
      exitCode: 0,
      columns: ['id', 'select_type'],
      rows: [
        ['1', 'SIMPLE'],
      ],
      affectedRows: 0,
      truncated: false,
    );
  }
}

class _BundledSqlite implements SqlDatabase, SqlScriptDatabase {
  _BundledSqlite(this.library);
  final String library;

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async => SqlQueryResult.fromNative(
    await SqliteFfi.invoke('query', {
      'databasePath': databasePath,
      'source': source,
      'params': parameters,
    }, libraryPath: library),
  );

  @override
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
  }) async => SqlScriptResult.fromNative(
    await SqliteFfi.invoke('executeScript', {
      'databasePath': databasePath,
      'source': source,
    }, libraryPath: library),
  );
}

class _FakeLibrary extends SqlQueryLibrary {
  _FakeLibrary({this.failOnRecord = false})
    : super(file: File('${Directory.systemTemp.path}/unused-tools.json'));

  final bool failOnRecord;
  final List<SqlHistoryEntry> _entries = [];

  @override
  List<SqlHistoryEntry> get history => List.unmodifiable(_entries);

  @override
  List<SqlSavedQuery> get saved => const [];

  @override
  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {
    if (failOnRecord) {
      throw const FileSystemException('磁盘写入失败');
    }
    _entries.insert(
      0,
      SqlHistoryEntry(
        database: database,
        source: source,
        executedAt: DateTime(2026, 10, 22),
        success: success,
      ),
    );
  }
}
