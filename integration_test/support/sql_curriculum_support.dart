import 'dart:convert';

import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_studio_core/content/content_repository.dart';

/// A complete script and its independently authored output.
class CurriculumScript {
  const CurriculumScript({
    required this.name,
    required this.exampleId,
    required this.source,
    required this.expected,
  });

  final String name;
  final String exampleId;
  final String source;
  final String expected;
}

class CurriculumCase {
  const CurriculumCase({
    required this.exampleId,
    required this.engine,
    required this.scripts,
  });

  final String exampleId;
  final String engine;
  final List<CurriculumScript> scripts;
}

/// Build execution coverage from the shipped catalog, including future entries.
/// Reject drift before running any script: a missing example must never reduce
/// the execution denominator silently.
List<CurriculumCase> curriculumCases(ContentCatalog catalog) {
  final lessons = {
    for (final tutorial in catalog.tutorials)
      for (final lesson in tutorial.lessons) lesson.id: lesson,
  };
  final lessonCount = catalog.tutorials.fold<int>(
    0,
    (count, tutorial) => count + tutorial.lessons.length,
  );
  if (lessons.length != lessonCount || lessons.isEmpty) {
    throw const FormatException(
      'Curriculum lesson IDs must be unique and nonempty.',
    );
  }
  final exampleIds = <String>{};
  final coveredLessons = <String>{};
  final cases = <CurriculumCase>[];
  for (final example in catalog.examples) {
    final lesson = lessons[example.sourceLessonId];
    if (!exampleIds.add(example.id) ||
        lesson == null ||
        !coveredLessons.add(example.sourceLessonId!)) {
      throw FormatException('Invalid curriculum mapping: ${example.id}');
    }
    if (example.code != lesson.code ||
        example.expectedOutput != lesson.output) {
      throw FormatException(
        'Lesson/example code or output drift: ${example.id}',
      );
    }
    final engine = example.inputFixtures['engine'];
    if (engine != 'sqlite' && engine != 'mysql') {
      throw FormatException(
        'Unsupported curriculum engine: ${example.id}: $engine',
      );
    }
    final setup = example.inputFixtures['exerciseSetup'];
    final raw = jsonDecode(
      example.inputFixtures['exerciseExpectedOutputs'] ?? 'null',
    );
    if (setup == null ||
        raw is! List ||
        raw.length != lesson.exercises.length ||
        raw.isEmpty ||
        raw.any((value) => value is! String || value.trim().isEmpty) ||
        example.expectedOutput.trim().isEmpty) {
      throw FormatException('Missing authored exercise output: ${example.id}');
    }
    final number = cases.length + 1;
    cases.add(
      CurriculumCase(
        exampleId: example.id,
        engine: engine!,
        scripts: [
          CurriculumScript(
            name: 'lesson_$number',
            exampleId: example.id,
            source: example.code,
            expected: example.expectedOutput,
          ),
          for (var index = 0; index < lesson.exercises.length; index++)
            CurriculumScript(
              name: 'exercise_${number}_$index',
              exampleId: example.id,
              source: '${setup.trimRight()}\n${lesson.exercises[index].answer}',
              expected: raw[index] as String,
            ),
        ],
      ),
    );
  }
  if (coveredLessons.length != lessons.length) {
    throw const FormatException(
      'Every shipped lesson requires one runnable example.',
    );
  }
  return List.unmodifiable(cases);
}

/// Checks all result sets and authored output; unavailable/truncated/partial
/// failure is never counted as a pass.
String verifyCurriculumOutput(
  SqlScriptResult script,
  CurriculumScript authored,
) {
  Never fail(String detail) =>
      throw StateError('${authored.exampleId}/${authored.name}: $detail');
  if (!script.available || !script.success || script.truncated) {
    fail('native script failed or truncated: ${script.error}');
  }
  if (script.results.isEmpty) {
    fail('native script returned no statement results');
  }
  for (final result in script.results) {
    if (!result.success || result.truncated) {
      fail('statement failed or truncated: ${result.error}');
    }
  }
  final queries = script.results
      .where((result) => result.columns.isNotEmpty)
      .toList();
  if (queries.isEmpty) {
    fail('expected a query result, including empty row sets');
  }
  final rows = queries.expand((result) => result.rows).toList();
  if (authored.expected.trim() == '(no rows)' && rows.isNotEmpty) {
    fail('expected no rows, received ${rows.length}');
  }
  final actual = normalizeCurriculumOutput(
    rows.map((row) => row.map((value) => value ?? '').join('|')).join('\n'),
  );
  final expected = authored.expected.trim() == '(no rows)'
      ? ''
      : normalizeCurriculumOutput(authored.expected);
  if (actual != expected) {
    fail(
      'authored output mismatch: expected ${jsonEncode(expected)}, '
      'actual ${jsonEncode(actual)}',
    );
  }
  return actual;
}

String normalizeCurriculumOutput(String text) => text
    .trim()
    .split('\n')
    .map((line) => line.trimRight())
    .where((line) => line.isNotEmpty)
    .join('\n');
