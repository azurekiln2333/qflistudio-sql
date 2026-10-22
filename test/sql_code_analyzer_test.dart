import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_code_analyzer.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_syntax_validator.dart';
import 'package:qfli_sql/sqlite_ffi.dart';
import 'package:qfli_studio_core/services/code_analysis.dart';

String _libraryPath() =>
    Platform.environment['QFLI_SQLITE_LIBRARY'] ??
    p.join(
      Directory.current.path,
      'native',
      'build',
      Platform.operatingSystem,
      Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
    );

/// Records engine use without touching a real backend.
class _SpyEngine implements SqlSyntaxEngine {
  _SpyEngine({this.result, this.error});

  final SqlEngineAnalysis? result;
  final Object? error;
  final texts = <String>[];

  @override
  Future<SqlEngineAnalysis> validate(String text) async {
    texts.add(text);
    if (error != null) throw error!;
    return result!;
  }
}

SqlEngineAnalysis _clean() => const SqlEngineAnalysis(
  engine: 'sqlite',
  version: '3.50.0',
  issues: [],
  skipped: [],
  statements: 1,
  checked: 1,
  schemaGaps: 0,
);

/// Builds a request for one active file plus optional extra open buffers.
CodeAnalysisRequest _request({
  required String root,
  required String active,
  required Map<String, String> documents,
  String language = 'sql',
  int revision = 7,
}) => CodeAnalysisRequest(
  projectPath: root,
  activeFilePath: active,
  language: language,
  revision: revision,
  documents: [
    for (final entry in documents.entries)
      CodeDocumentSnapshot(
        path: entry.key,
        text: entry.value,
        revision: revision,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = _libraryPath();
  final missingLibrary = !File(library).existsSync();
  late Directory root;
  late String activeFile;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli_sql_analyzer_');
    activeFile = p.join(root.path, 'main.sql');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('snapshot ownership and dialects', () {
    test('rejects an active file outside the project root', () async {
      final result = await const SqlCodeAnalyzer().analyze(
        _request(
          root: p.join(root.path, 'project'),
          active: p.join(root.path, 'other', 'main.sql'),
          documents: {p.join(root.path, 'other', 'main.sql'): "SELECT 'x"},
        ),
      );
      expect(result.unavailableReason, contains('不在当前项目内'));
      expect(result.diagnostics, isEmpty);
    });

    test('rejects a non-SQL active file', () async {
      final result = await const SqlCodeAnalyzer().analyze(
        _request(
          root: root.path,
          active: p.join(root.path, 'notes.md'),
          documents: {p.join(root.path, 'notes.md'): "SELECT 'x"},
        ),
      );
      expect(result.unavailableReason, contains('不在当前项目内'));
    });

    test('requires the exact unsaved snapshot of the active file', () async {
      final result = await const SqlCodeAnalyzer().analyze(
        _request(
          root: root.path,
          active: activeFile,
          documents: {p.join(root.path, 'other.sql'): 'SELECT 1;'},
        ),
      );
      expect(result.unavailableReason, contains('没有当前 SQL 文件的未保存快照'));
    });

    test('ignores foreign and non-SQL buffers in the request', () async {
      final spy = _SpyEngine(result: _clean());
      final result = await SqlCodeAnalyzer(engine: spy).analyze(
        _request(
          root: root.path,
          active: activeFile,
          documents: {
            activeFile: 'SELECT 1;',
            p.join(root.path, 'sub', 'broken.sql'): "SELECT 'x",
            p.join(root.path, 'notes.txt'): "SELECT 'x",
            p.join(root.path, '..', 'escape.sql'): "SELECT 'x",
          },
        ),
      );
      expect(result.unavailableReason, isNull);
      // `sub/broken.sql` is inside the project, so its unsaved text is analyzed;
      // the foreign `.sql` and the non-SQL buffer are not.
      expect(result.diagnostics.map((problem) => problem.filePath), [
        p.join(root.path, 'sub', 'broken.sql'),
      ]);
      expect(spy.texts, ['SELECT 1;']);
    });

    test(
      'analyzes every owned open SQL buffer with the exact unsaved text',
      () async {
        final spy = _SpyEngine(result: _clean());
        final second = p.join(root.path, 'other.sql');
        final result = await SqlCodeAnalyzer(engine: spy).analyze(
          _request(
            root: root.path,
            active: activeFile,
            documents: {activeFile: 'SELECT 1;', second: "SELECT 'x"},
          ),
        );
        final lexical = result.diagnostics.where(
          (problem) => problem.code == 'unterminated-string',
        );
        expect(lexical, hasLength(1));
        expect(lexical.single.filePath, second);
        expect(lexical.single.startOffset, 7);
        expect(lexical.single.severity, CodeDiagnosticSeverity.error);
        // Engine checking stays on the active buffer only.
        expect(spy.texts, ['SELECT 1;']);
      },
    );
  });

  group('saved file is never used as the analyzed text', () {
    test('reports the unsaved buffer, not the saved file', () async {
      final saved = File(activeFile)..writeAsStringSync("SELECT 'unterminated");
      final result = await SqlCodeAnalyzer(engine: _SpyEngine(result: _clean()))
          .analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: 'SELECT 1;'},
            ),
          );
      expect(result.diagnostics, isEmpty);
      expect(result.unavailableReason, isNull);
      expect(saved.readAsStringSync(), "SELECT 'unterminated");

      final unsaved =
          await SqlCodeAnalyzer(engine: _SpyEngine(result: _clean())).analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: "SELECT 'unterminated"},
            ),
          );
      expect(unsaved.diagnostics.single.message, contains('未结束'));
      expect(
        unsaved.diagnostics.single.endOffset,
        "SELECT 'unterminated".length,
      );
      expect(saved.readAsStringSync(), "SELECT 'unterminated");
    });

    test('keeps CRLF and emoji positions in UTF-16 code units', () async {
      const text = "SELECT '😀';\r\nSELECT 'open";
      final result = await SqlCodeAnalyzer(engine: _SpyEngine(result: _clean()))
          .analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: text},
            ),
          );
      final problem = result.diagnostics.single;
      expect(problem.startOffset, text.indexOf("'open"));
      expect(problem.endOffset, text.length);
      expect(text.substring(problem.startOffset, problem.endOffset), "'open");
      // The emoji counts as two UTF-16 code units and CRLF as two more.
      expect(problem.startOffset, 21);
    });

    test('never lets a range exceed the snapshot text', () async {
      const text = "SELECT 'x";
      final result = await SqlCodeAnalyzer(engine: _SpyEngine(result: _clean()))
          .analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: text},
            ),
          );
      for (final problem in result.diagnostics) {
        expect(problem.startOffset, inInclusiveRange(0, text.length));
        expect(problem.endOffset, inInclusiveRange(0, text.length));
        expect(problem.endOffset, greaterThanOrEqualTo(problem.startOffset));
      }
    });
  });

  group('honest unavailable and unsupported states', () {
    test(
      'surfaces an unavailable backend instead of reporting clean',
      () async {
        final result =
            await SqlCodeAnalyzer(
              engine: _SpyEngine(
                result: const SqlEngineAnalysis(
                  engine: 'sqlite',
                  version: '',
                  issues: [],
                  skipped: [],
                  statements: 0,
                  checked: 0,
                  schemaGaps: 0,
                  unavailableReason: '当前平台尚未提供 SQLite 语法校验接口',
                ),
              ),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: 'SELECT 1;'},
              ),
            );
        expect(result.diagnostics, isEmpty);
        expect(result.unavailableReason, contains('尚未提供'));
      },
    );

    test('surfaces a backend exception instead of reporting clean', () async {
      final result =
          await SqlCodeAnalyzer(
            engine: _SpyEngine(error: StateError('bridge missing')),
          ).analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: 'SELECT 1;'},
            ),
          );
      expect(result.unavailableReason, contains('bridge missing'));
      expect(result.diagnostics, isEmpty);
    });

    test('a MySQL project is never checked with SQLite grammar', () async {
      final marker = File(p.join(root.path, '.qfli', 'mysql.json'));
      marker.parent.createSync(recursive: true);
      marker.writeAsStringSync(jsonEncode({'schema': 'qfli_project_abc'}));
      final spy = _SpyEngine(result: _clean());
      final result = await SqlCodeAnalyzer(engine: spy).analyze(
        _request(
          root: root.path,
          active: activeFile,
          documents: {activeFile: 'SELECT `col` FROM t WHERE;'},
        ),
      );
      expect(spy.texts, isEmpty);
      expect(result.unavailableReason, contains('MySQL'));
      expect(result.diagnostics, isEmpty);
    });

    test(
      'MySQL dialect keeps lexical checks with a documented reason',
      () async {
        File(p.join(root.path, '.qfli', 'mysql.json'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'schema': 'qfli_project_abc'}));
        final result =
            await SqlCodeAnalyzer(
              engine: _SpyEngine(error: StateError('must not be called')),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                // MySQL requires whitespace after `--`, so this string is open.
                documents: {activeFile: "SELECT 5--'open"},
              ),
            );
        expect(result.diagnostics.single.code, 'unterminated-string');
        expect(result.unavailableReason, contains('MySQL'));
      },
    );

    test('NUL text is reported and never reaches the engine', () async {
      const text = 'SELECT 1\x00SELECT 2';
      final spy = _SpyEngine(result: _clean());
      final result = await SqlCodeAnalyzer(engine: spy).analyze(
        _request(
          root: root.path,
          active: activeFile,
          documents: {activeFile: text},
        ),
      );
      expect(spy.texts, isEmpty);
      expect(result.diagnostics.single.code, 'nul-character');
      expect(result.unavailableReason, contains('NUL'));
    });

    test('oversize text skips the engine with a visible reason', () async {
      final spy = _SpyEngine(result: _clean());
      final result = await SqlCodeAnalyzer(engine: spy, maxEngineUnits: 4)
          .analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: 'SELECT 1;'},
            ),
          );
      expect(spy.texts, isEmpty);
      expect(result.unavailableReason, contains('UTF-16'));
    });

    test(
      'an early prepare failure reports incomplete engine coverage',
      () async {
        const text = 'SELECT * FROM missing; SELECT 1 FROM;';
        final result =
            await SqlCodeAnalyzer(
              engine: _SpyEngine(
                result: const SqlEngineAnalysis(
                  engine: 'sqlite',
                  version: '3.50.0',
                  issues: [],
                  skipped: [],
                  statements: 1,
                  checked: 1,
                  schemaGaps: 1,
                  truncated: true,
                ),
              ),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: text},
              ),
            );
        final coverage = result.diagnostics.singleWhere(
          (problem) => problem.code == 'engine-truncated',
        );
        expect(coverage.severity, CodeDiagnosticSeverity.information);
        expect(coverage.message, contains('未完整'));
        expect(coverage.message, isNot(contains('512')));
        expect(
          result.diagnostics
              .singleWhere((problem) => problem.code == 'schema-gap')
              .message,
          contains('部分语法及类型问题可能尚未检查'),
        );
      },
    );

    test(
      'schema gaps and skipped statements are visible information',
      () async {
        final result =
            await SqlCodeAnalyzer(
              engine: _SpyEngine(
                result: const SqlEngineAnalysis(
                  engine: 'sqlite',
                  version: '3.50.0',
                  issues: [],
                  skipped: [
                    SqlSkippedStatement(
                      startOffset: 2,
                      endOffset: 9,
                      keyword: 'PRAGMA',
                      reason: 'PRAGMA 可能在 prepare 阶段修改数据库状态',
                    ),
                  ],
                  statements: 2,
                  checked: 1,
                  schemaGaps: 1,
                ),
              ),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: 'SELECT 1 FROM missing;'},
              ),
            );
        expect(result.unavailableReason, isNull);
        final codes = result.diagnostics
            .map((problem) => problem.code)
            .toList();
        expect(codes, containsAll(['statement-skipped', 'schema-gap']));
        expect(
          result.diagnostics.every(
            (problem) => problem.severity == CodeDiagnosticSeverity.information,
          ),
          isTrue,
        );
      },
    );

    test('engine syntax errors keep their source offsets', () async {
      const text = 'SELECT 1 FROM;';
      final result =
          await SqlCodeAnalyzer(
            engine: _SpyEngine(
              result: const SqlEngineAnalysis(
                engine: 'sqlite',
                version: '3.50.0',
                issues: [
                  SqlEngineIssue(
                    startOffset: 13,
                    endOffset: 13,
                    message: 'near ";": syntax error',
                    code: 'sqlite-syntax-offset',
                  ),
                ],
                skipped: [],
                statements: 1,
                checked: 1,
                schemaGaps: 0,
              ),
            ),
          ).analyze(
            _request(
              root: root.path,
              active: activeFile,
              documents: {activeFile: text},
            ),
          );
      final problem = result.diagnostics.single;
      expect(problem.severity, CodeDiagnosticSeverity.error);
      expect(problem.filePath, activeFile);
      expect(text.substring(problem.startOffset), ';');
    });
  });

  group(
    'real prepare-only SQLite engine',
    () {
      Future<SqlEngineAnalysis> validate(String text) =>
          SqlitePrepareSyntaxEngine(libraryPath: library).validate(text);

      test(
        'actually runs the bundled engine and reports its version',
        () async {
          final analysis = await validate('SELECT 1;');
          expect(analysis.unavailableReason, isNull);
          expect(analysis.engine, 'sqlite');
          expect(analysis.version, isNotEmpty);
          expect(analysis.statements, 1);
          expect(analysis.checked, 1);
          expect(analysis.issues, isEmpty);
        },
      );

      test('reports a real syntax error through the analyzer', () async {
        final result =
            await SqlCodeAnalyzer(
              engine: SqlitePrepareSyntaxEngine(libraryPath: library),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: 'SELECT 1 FROM;'},
              ),
            );
        expect(result.unavailableReason, isNull);
        final errors = result.diagnostics.where(
          (problem) => problem.severity == CodeDiagnosticSeverity.error,
        );
        expect(errors, hasLength(1));
        expect(errors.single.message, isNotEmpty);
        expect(errors.single.startOffset, inInclusiveRange(0, 14));
      });

      test('maps sqlite3_error_offset bytes to UTF-16 code units', () async {
        // The emoji is four UTF-8 bytes but two UTF-16 code units, so a naive
        // byte offset would land two units late.
        const text = "SELECT '😀' AS a, '中文' AS b, FROM;";
        final analysis = await validate(text);
        expect(analysis.issues, hasLength(1));
        final offset = analysis.issues.first.startOffset;
        expect(analysis.issues.first.code, 'sqlite-syntax-offset');
        expect(text.substring(offset), startsWith('FROM'));
        expect(offset, text.indexOf('FROM'));
        // The UTF-8 byte prefix is longer, proving a real conversion happened.
        expect(utf8.encode(text.substring(0, offset)).length, 35);
        expect(
          utf8.encode(text.substring(0, offset)).length,
          greaterThan(offset),
        );
      });

      test('reports a statement range when the engine has no offset', () async {
        // SQLite returns -1 for an incomplete statement, so no precise position
        // is invented; the diagnostic sits at the statement start.
        const text = 'SELECT 1 FROM';
        final analysis = await validate(text);
        expect(analysis.issues, hasLength(1));
        expect(analysis.issues.first.code, 'sqlite-syntax');
        expect(analysis.issues.first.startOffset, 0);
        expect(analysis.issues.first.endOffset, 0);
        expect(analysis.issues.first.message, isNotEmpty);
      });

      test('missing schema is not a syntax error and is not clean', () async {
        const source =
            'SELECT * FROM missing_table; SELECT missing_column FROM missing_table;';
        final analysis = await validate(source);
        expect(analysis.unavailableReason, isNull);
        expect(analysis.issues, isEmpty);
        expect(analysis.schemaGaps, 1);
        expect(analysis.checked, 1);
        expect(analysis.truncated, isTrue);
        expect(analysis.skipped.single.endOffset, source.length);
        final mixed = await validate(
          'SELECT * FROM missing_table; SELECT 1 FROM;',
        );
        expect(mixed.schemaGaps, 1);
        expect(mixed.issues, isEmpty);
        expect(mixed.checked, 1);
        expect(mixed.truncated, isTrue);
        expect(mixed.skipped.single.reason, contains('后续 SQL 未完整检查'));
        final result =
            await SqlCodeAnalyzer(
              engine: SqlitePrepareSyntaxEngine(libraryPath: library),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: 'SELECT * FROM missing_table;'},
              ),
            );
        final gap = result.diagnostics.singleWhere(
          (diagnostic) => diagnostic.code == 'schema-gap',
        );
        expect(gap.severity, CodeDiagnosticSeverity.information);
      });

      test('refuses side-effecting statements without preparing them', () async {
        const text =
            'PRAGMA journal_mode = DELETE; '
            "ATTACH DATABASE 'attached.db' AS other; "
            'SELECT 1;';
        final analysis = await validate(text);
        expect(analysis.skipped, hasLength(1));
        expect(analysis.skipped.map((statement) => statement.keyword), [
          'PRAGMA',
        ]);
        expect(analysis.checked, 0);
        expect(analysis.statements, 1);
        expect(analysis.truncated, isTrue);
        expect(analysis.skipped.single.endOffset, text.length);
        // The refused statements never reach the engine, so no database file is
        // created next to the analyzed project.
        expect(
          root.listSync().map((entity) => p.basename(entity.path)),
          isNot(contains('attached.db')),
        );
      });

      test(
        'the authorizer also refuses a guarded operation after a BOM',
        () async {
          const text = '\uFEFFPRAGMA user_version = 1; SELECT 1 FROM;';
          final analysis = await validate(text);
          expect(analysis.unavailableReason, isNull);
          expect(analysis.checked, 1);
          expect(analysis.issues, isEmpty);
          expect(analysis.truncated, isTrue);
          expect(analysis.skipped.single.reason, contains('拒绝'));
          expect(analysis.skipped.single.endOffset, text.length);
        },
      );

      test('native tails preserve later UTF-16 syntax-error positions', () async {
        const text =
            "SELECT '😀';\r\nCREATE TABLE trigger (begin);\r\nSELECT '中文', FROM;";
        final analysis = await validate(text);
        expect(analysis.unavailableReason, isNull);
        expect(analysis.checked, 3);
        expect(analysis.issues.single.startOffset, text.indexOf('FROM'));
        expect(analysis.truncated, isTrue);
        expect(analysis.skipped.single.endOffset, text.length);
      });

      test(
        'keyword column names in valid triggers cannot create false errors',
        () async {
          for (final column in ['begin', 'end']) {
            final valid =
                'CREATE TABLE t ($column INTEGER); '
                'CREATE TRIGGER tr AFTER INSERT ON t BEGIN '
                'UPDATE t SET $column = 1; END; SELECT 1;';
            // Prove validity with the same bundled engine on a separate,
            // disposable database; validation itself must not execute this DDL.
            final execution = await SqliteFfi.invoke('executeScript', {
              'source': valid,
              'databasePath': ':memory:',
            }, libraryPath: library);
            expect(execution['exitCode'], 0, reason: column);

            final text = '$valid SELECT 1 FROM;';
            final analysis = await validate(text);
            expect(analysis.unavailableReason, isNull, reason: column);
            expect(analysis.issues, isEmpty, reason: column);
            expect(analysis.schemaGaps, 1, reason: column);
            expect(analysis.checked, 2, reason: column);
            expect(analysis.truncated, isTrue, reason: column);
            final remaining = analysis.skipped.single;
            expect(
              remaining.startOffset,
              lessThan(text.lastIndexOf('SELECT 1 FROM')),
            );
            expect(remaining.endOffset, text.length);
            expect(remaining.reason, contains('后续 SQL 未完整检查'));
          }
        },
      );

      test(
        'a refused first statement leaves the whole remainder unvalidated',
        () async {
          const limit = 512;
          final analysis = await validate(
            'PRAGMA user_version; ' * (limit + 1),
          );
          expect(analysis.unavailableReason, isNull);
          expect(analysis.statements, 1);
          expect(analysis.checked, 0);
          expect(analysis.skipped, hasLength(1));
          expect(analysis.truncated, isTrue);
        },
      );

      test(
        'a keyword table name cannot bypass the validation budget',
        () async {
          final analysis = await validate(
            'CREATE TABLE trigger (begin); ${'SELECT 1; ' * 512}',
          );
          expect(analysis.unavailableReason, isNull);
          expect(analysis.statements, 513);
          expect(analysis.checked, 512);
          expect(analysis.truncated, isTrue);
          expect(analysis.issues, isEmpty);
        },
      );

      test('analyzing destructive SQL writes nothing', () async {
        final database = p.join(root.path, 'data.sqlite');
        final created = await const NativeSqliteDatabase().executeScript(
          databasePath: database,
          source:
              'CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT); '
              "INSERT INTO people (name) VALUES ('Ada');",
        );
        expect(created.success, isTrue, reason: created.error);
        final before = File(database).readAsBytesSync();
        final beforeFiles = root.listSync(recursive: true).length;

        const destructive =
            'DROP TABLE people; DELETE FROM people; '
            'UPDATE people SET name = NULL; '
            'INSERT INTO people (name) VALUES (\'Eve\'); '
            'CREATE TABLE extra (a INTEGER); '
            'PRAGMA journal_mode = DELETE;';
        final analysis = await validate(destructive);
        expect(analysis.unavailableReason, isNull);
        expect(analysis.checked, greaterThan(0));
        // Nothing was stepped, so no table can exist in the user database.
        expect(File(database).readAsBytesSync(), before);
        expect(root.listSync(recursive: true), hasLength(beforeFiles));
        final rows = await SqliteFfi.invoke('query', {
          'databasePath': database,
          'source': 'SELECT name FROM people;',
          'params': <String?>[],
        }, libraryPath: library);
        expect(rows['rows'], [
          ['Ada'],
        ]);
      });

      test(
        'external state functions remain unvalidated without file changes',
        () async {
          final target = p.join(root.path, 'extension-marker');
          final analysis = await validate(
            "SELECT load_extension('${target.replaceAll("'", "''")}');",
          );
          expect(analysis.unavailableReason, isNull);
          // Builds that omit extension loading reject the missing function before
          // the authorizer sees it. Both states remain explicitly unvalidated.
          expect(analysis.skipped, hasLength(1));
          expect(analysis.schemaGaps, inInclusiveRange(0, 1));
          if (analysis.skipped.isNotEmpty) {
            expect(analysis.skipped.single.reason, contains('未完整检查'));
          }
          expect(analysis.issues, isEmpty);
          expect(File(target).existsSync(), isFalse);
        },
      );

      test('analyzer never writes project files', () async {
        final source = File(activeFile)..writeAsStringSync("SELECT 'open");
        final before = root.listSync(recursive: true).length;
        final saved = source.readAsStringSync();
        final result =
            await SqlCodeAnalyzer(
              engine: SqlitePrepareSyntaxEngine(libraryPath: library),
            ).analyze(
              _request(
                root: root.path,
                active: activeFile,
                documents: {activeFile: saved},
              ),
            );
        expect(result.diagnostics, isNotEmpty);
        expect(source.readAsStringSync(), "SELECT 'open");
        expect(root.listSync(recursive: true), hasLength(before));
        expect(Directory(p.join(root.path, '.qfli')).existsSync(), isFalse);
      });

      test('rejects a caller-supplied database path', () async {
        await expectLater(
          SqliteFfi.invoke('validate', {
            'source': 'SELECT 1;',
            'databasePath': p.join(root.path, 'user.sqlite'),
          }, libraryPath: library),
          throwsArgumentError,
        );
        expect(File(p.join(root.path, 'user.sqlite')).existsSync(), isFalse);
      });

      test(
        'multi-statement scripts with trigger bodies are validated',
        () async {
          const text =
              'CREATE TABLE t (a INTEGER); '
              'CREATE TRIGGER tr AFTER INSERT ON t BEGIN '
              'UPDATE t SET a = CASE WHEN a > 0 THEN 1 ELSE 0 END; END; '
              'SELECT 1;';
          final analysis = await validate(text);
          expect(analysis.unavailableReason, isNull);
          expect(analysis.checked, 2);
          expect(analysis.issues, isEmpty);
          expect(analysis.truncated, isTrue);
          expect(analysis.skipped.single.endOffset, text.length);
        },
      );
    },
    skip: missingLibrary
        ? 'Build the bundled SQLite library ($library) to run real engine tests.'
        : false,
  );

  // This group must stay last: loading the real preference is cached for the
  // process, so a MySQL selection would affect later assertions.
  group('selected engine dialect', () {
    test('the selected MySQL engine also selects the MySQL dialect', () async {
      final storage = Directory(p.join(root.path, 'app_storage'))
        ..createSync(recursive: true);
      File(
        p.join(storage.path, 'sql_engine.json'),
      ).writeAsStringSync('{"engine":"localMysql"}');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => storage.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await SqlEnginePreference.load();
      expect(SqlEnginePreference.current, SqlEngineKind.localMysql);

      final spy = _SpyEngine(result: _clean());
      final result = await SqlCodeAnalyzer(engine: spy).analyze(
        _request(
          root: root.path,
          active: activeFile,
          documents: {activeFile: 'SELECT 1;'},
        ),
      );
      expect(spy.texts, isEmpty);
      expect(result.unavailableReason, contains('MySQL'));
    });
  });
}
