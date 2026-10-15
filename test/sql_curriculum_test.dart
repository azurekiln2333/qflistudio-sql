import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_content_repository.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

/// Loads a real bundled asset for parsing assertions.
Future<String> _asset(String key) async => await rootBundle.loadString(key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQL curriculum assets', () {
    test('tutorials.json parses via the shared catalog contract', () async {
      final source = await _asset(SqlContentRepository.tutorialAsset);
      final catalog = ContentCatalog.fromJson(
        tutorialsSource: source,
        examplesSource: await _asset(SqlContentRepository.exampleAsset),
      );

      final sqlTutorials = catalog.tutorials
          .where((entry) => entry.type == 'sql')
          .toList();
      final sqlExamples = catalog.examples
          .where((entry) => entry.type == 'sql')
          .toList();

      expect(sqlTutorials.length, greaterThanOrEqualTo(110));
      expect(sqlExamples.length, greaterThanOrEqualTo(110));
      expect(sqlTutorials.length, sqlExamples.length);
    });

    test('every lesson has complete fields and a reference exercise', () async {
      final catalog = ContentCatalog.fromJson(
        tutorialsSource: await _asset(SqlContentRepository.tutorialAsset),
        examplesSource: await _asset(SqlContentRepository.exampleAsset),
      );

      for (final tutorial in catalog.tutorials) {
        expect(tutorial.id, isNotEmpty);
        expect(tutorial.type, 'sql');
        expect(tutorial.lessons, isNotEmpty);
        for (final lesson in tutorial.lessons) {
          expect(lesson.title, isNotEmpty, reason: tutorial.id);
          expect(lesson.summary, isNotEmpty, reason: tutorial.id);
          expect(lesson.explain, isNotEmpty, reason: tutorial.id);
          expect(lesson.code, isNotEmpty, reason: tutorial.id);
          expect(lesson.output, isNotEmpty, reason: tutorial.id);
          expect(lesson.objective, isNotEmpty, reason: tutorial.id);
          expect(lesson.exercises, isNotEmpty, reason: tutorial.id);
          for (final exercise in lesson.exercises) {
            expect(exercise.prompt, isNotEmpty, reason: tutorial.id);
            expect(exercise.answer, isNotEmpty, reason: tutorial.id);
          }
        }
      }
    });

    test(
      'no placeholder tokens and no duplicated explain/code bodies',
      () async {
        final catalog = ContentCatalog.fromJson(
          tutorialsSource: await _asset(SqlContentRepository.tutorialAsset),
          examplesSource: await _asset(SqlContentRepository.exampleAsset),
        );

        final explains = <String>{};
        final codes = <String>{};
        final placeholders = RegExp(r'TODO|FIXME|placeholder|占位符|待补充');
        for (final tutorial in catalog.tutorials) {
          for (final lesson in tutorial.lessons) {
            expect(
              placeholders.hasMatch(lesson.explain),
              isFalse,
              reason: '${tutorial.id} explain',
            );
            expect(
              explains.add(lesson.explain),
              isTrue,
              reason: '${tutorial.id} duplicated explain',
            );
            expect(
              codes.add(lesson.code),
              isTrue,
              reason: '${tutorial.id} duplicated code',
            );
          }
        }
      },
    );

    test('dialect/version is visible in display fields', () async {
      final catalog = ContentCatalog.fromJson(
        tutorialsSource: await _asset(SqlContentRepository.tutorialAsset),
        examplesSource: await _asset(SqlContentRepository.exampleAsset),
      );

      for (final tutorial in catalog.tutorials) {
        final text = '${tutorial.summary} ${tutorial.concepts.join(' ')}';
        expect(
          text.contains('SQLite') || text.contains('MySQL'),
          isTrue,
          reason: '${tutorial.id} must state dialect/version in display fields',
        );
      }
    });

    test(
      'examples carry their own runnable code and expected output',
      () async {
        final catalog = ContentCatalog.fromJson(
          tutorialsSource: await _asset(SqlContentRepository.tutorialAsset),
          examplesSource: await _asset(SqlContentRepository.exampleAsset),
        );

        for (final example in catalog.examples) {
          expect(example.code, isNotEmpty, reason: example.id);
          expect(example.expectedOutput, isNotEmpty, reason: example.id);
          // Example code must be a full script, not just a SELECT.
          expect(
            example.code.toUpperCase(),
            contains('CREATE '),
            reason: '${example.id} must include setup DDL',
          );
        }
      },
    );
  });

  group('SqlContentRepository', () {
    test('loads, filters by sql, and memoizes the catalog', () async {
      final repository = SqlContentRepository();
      final catalog = await repository.load();
      expect(catalog.tutorials, isNotEmpty);

      final tutorials = await repository.tutorials(
        filter: ContentFilter.forProduct('sqlab'),
      );
      expect(tutorials, isNotEmpty);
      expect(tutorials.every((entry) => entry.type == 'sql'), isTrue);

      // Second load returns the same memoized instance.
      expect(identical(await repository.load(), catalog), isTrue);
    });

    test('examples filter returns sql examples', () async {
      final repository = SqlContentRepository();
      final examples = await repository.examples(
        filter: const ContentFilter(language: 'sql'),
      );
      expect(examples, isNotEmpty);
      expect(examples.every((entry) => entry.type == 'sql'), isTrue);
    });

    test('missing asset surfaces a descriptive exception', () async {
      final repository = SqlContentRepository(bundle: _EmptyBundle());
      await expectLater(
        repository.load(),
        throwsA(isA<SqlContentAssetException>()),
      );
    });
  });
}

/// A bundle that fails every lookup, used to test the error path.
class _EmptyBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('missing $key');
  }
}
