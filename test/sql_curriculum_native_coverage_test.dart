import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_content_repository.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

import '../integration_test/support/sql_curriculum_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ContentCatalog> load({String? examples}) async =>
      ContentCatalog.fromJson(
        tutorialsSource: await rootBundle.loadString(
          SqlContentRepository.tutorialAsset,
        ),
        examplesSource:
            examples ??
            await rootBundle.loadString(SqlContentRepository.exampleAsset),
      );

  Future<Map<String, dynamic>> exampleDocument() async =>
      jsonDecode(await rootBundle.loadString(SqlContentRepository.exampleAsset))
          as Map<String, dynamic>;

  test('coverage rejects omitted shipped examples', () async {
    final raw = await exampleDocument();
    (raw['entries'] as List<dynamic>).removeLast();
    final catalog = await load(examples: jsonEncode(raw));
    expect(() => curriculumCases(catalog), throwsFormatException);
  });

  test('coverage rejects code drift and unsupported engine fixtures', () async {
    var raw = await exampleDocument();
    var first = (raw['entries'] as List<dynamic>).first as Map<String, dynamic>;
    first['code'] = 'SELECT 999;';
    var catalog = await load(examples: jsonEncode(raw));
    expect(() => curriculumCases(catalog), throwsFormatException);

    raw = await exampleDocument();
    first = (raw['entries'] as List<dynamic>).first as Map<String, dynamic>;
    (first['inputFixtures'] as Map<String, dynamic>)['engine'] = 'unavailable';
    catalog = await load(examples: jsonEncode(raw));
    expect(() => curriculumCases(catalog), throwsFormatException);
  });

  test('a NULL row cannot pass an authored no-rows expectation', () {
    const response = SqlQueryResult(
      available: true,
      exitCode: 0,
      columns: ['value'],
      rows: [
        [null],
      ],
      affectedRows: 0,
      truncated: false,
    );
    expect(
      () => verifyCurriculumOutput(
        const SqlScriptResult(summary: response, results: [response]),
        const CurriculumScript(
          name: 'empty',
          exampleId: 'fixture',
          source: 'SELECT NULL;',
          expected: '(no rows)',
        ),
      ),
      throwsStateError,
    );
  });

  final library =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
      );
  test(
    'every shipped SQLite example and exercise matches the bundled C engine',
    () async {
      final catalog = await load();
      final cases = curriculumCases(catalog);
      final sqliteCases = cases
          .where((entry) => entry.engine == 'sqlite')
          .toList();
      final mysqlCases = cases
          .where((entry) => entry.engine == 'mysql')
          .toList();
      expect(sqliteCases.length + mysqlCases.length, catalog.examples.length);
      expect(sqliteCases, isNotEmpty);
      expect(mysqlCases, isNotEmpty);
      const database = NativeSqliteDatabase();
      final identity = await database.query(
        databasePath: ':memory:',
        source: 'SELECT sqlite_version()',
      );
      expect(identity.success, isTrue, reason: identity.error);
      expect(identity.rows.single.single, startsWith('3.50.'));
      var checked = 0;
      for (final entry in sqliteCases) {
        for (final authored in entry.scripts) {
          final result = await database.executeScript(
            databasePath: ':memory:',
            source: authored.source,
          );
          verifyCurriculumOutput(result, authored);
          checked++;
        }
      }
      expect(
        checked,
        sqliteCases.fold<int>(
          0,
          (count, entry) => count + entry.scripts.length,
        ),
      );
      stdout.writeln(
        'QFLI_SQL_CURRICULUM_HOST sqliteExamples=${sqliteCases.length} '
        'sqliteScripts=$checked mysqlNotExecuted=${mysqlCases.length}',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: !File(library).existsSync()
        ? 'Bundled SQLite runtime missing: no native curriculum pass claimed.'
        : false,
  );
}
