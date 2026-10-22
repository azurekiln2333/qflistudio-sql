import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/main.dart';
import 'package:qfli_sql/sql_code_analyzer.dart';
import 'package:qfli_sql/sql_content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';
import 'package:qfli_studio_core/widgets/language_badge.dart';
// Public editor APIs expose these types through the shared core dependency.
// ignore: depend_on_referenced_packages
import 'package:re_editor/re_editor.dart';
// ignore: depend_on_referenced_packages
import 'package:re_highlight/re_highlight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  StudioProfile? previousProfile;
  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = sqlProfile;
  });
  tearDown(() => StudioProfile.current = previousProfile);

  for (final tutorials in [true, false]) {
    testWidgets(
      'real SQL ${tutorials ? 'tutorials' : 'examples'} filter and badges at 320px / 2x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = SqlContentRepository();
        final catalog = await tester.runAsync(repository.load);
        expect(catalog, isNotNull);
        // This gate deliberately covers the shipped catalog before expansion.
        expect(catalog!.tutorials, hasLength(126));
        expect(catalog.examples, hasLength(126));
        final title = tutorials
            ? catalog.tutorials.last.lessons.last.title
            : catalog.examples.last.title;
        final code = tutorials
            ? catalog.tutorials.last.lessons.last.code
            : catalog.examples.last.code;
        await tester.pumpWidget(
          _app(
            tutorials
                ? LocalTutorialsTab(language: 'sql', repository: repository)
                : ExampleCodeTab(language: 'sql', repository: repository),
            scale: 2,
          ),
        );
        await _until(
          tester,
          () =>
              find.byKey(const ValueKey('content-query')).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(tutorials ? '126 lessons' : '126 examples'),
          findsOneWidget,
        );
        final sqlChip = find.byKey(const ValueKey('content-language-sql'));
        expect(sqlChip, findsOneWidget);
        expect(find.byKey(const ValueKey('content-language-c')), findsNothing);
        await tester.tap(sqlChip);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(sqlChip).selected, isTrue);
        final titles = tutorials
            ? catalog.tutorials.expand(
                (entry) => entry.lessons.map((lesson) => lesson.title),
              )
            : catalog.examples.map((entry) => entry.title);
        // Exercise every catalog title through the real filter and lazy list.
        // A metadata-only count cannot catch a hidden final row or a lost badge.
        for (final itemTitle in titles) {
          final query = find.byKey(const ValueKey('content-query'));
          await tester.ensureVisible(query);
          await tester.enterText(query, itemTitle);
          await tester.pumpAndSettle();
          final itemRow = find.ancestor(
            of: find.text(itemTitle),
            matching: find.byType(ListTile),
          );
          expect(itemRow, findsOneWidget, reason: itemTitle);
          await tester.ensureVisible(itemRow);
          expect(
            tester
                .widget<LanguageBadge>(
                  find.descendant(
                    of: itemRow,
                    matching: find.byType(LanguageBadge),
                  ),
                )
                .language,
            'sql',
            reason: itemTitle,
          );
        }
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(row);
        final badge = tester.widget<LanguageBadge>(
          find.descendant(of: row, matching: find.byType(LanguageBadge)),
        );
        expect(languageLabel(badge.language), 'SQL');
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LanguageBadge>(
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(LanguageBadge),
                ),
              )
              .language,
          'sql',
        );
        // The detail route must use the SQL asset, including its authored code.
        await tester.scrollUntilVisible(
          find.byType(CodeSnippet),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        final snippet = tester.widget<CodeSnippet>(
          find.byType(CodeSnippet).first,
        );
        expect(snippet.example.type, 'sql');
        expect(snippet.example.code, code);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        final reset = find.byKey(const ValueKey('content-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(
          find.text(tutorials ? '126 lessons' : '126 examples'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'SQL profile and catalog import preserve SQL source and existing entry',
    () async {
      expect(sqlProfile.codeAnalyzer, isA<SqlCodeAnalyzer>());
      expect(sqlProfile.offlineOnly, isTrue);
      expect(sqlProfile.supportedFileExtensions, ['.sql']);
      final examples = await LocalContentAdapter.loadExamples(
        repository: SqlContentRepository(),
        language: 'sql',
        productKey: sqlProfile.productKey,
      );
      expect(examples, hasLength(126));
      final directory = Directory.systemTemp.createTempSync(
        'qfli_sql_core_import_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final entry = File(p.join(directory.path, 'main.sql'))
        ..writeAsStringSync('SELECT 1;');
      final project = Project.create(
        name: 'SQL import',
        path: directory.path,
        type: 'sql',
        language: 'SQL',
      );
      await ProjectConfig.write(
        projectRoot: directory.path,
        name: project.name,
        language: project.language,
        entryFile: 'main.sql',
      );
      final config = File(
        ProjectConfig.configPath(directory.path),
      ).readAsStringSync();
      final example = examples.last;
      expect(CodeImportService.suggestedFileName(example.type), 'main.sql');
      final imported = await CodeImportService.importIntoProject(
        project: project,
        example: example,
        fileName: 'imported.sql',
      );
      expect(imported.path, p.join(directory.path, 'src', 'imported.sql'));
      expect(File(imported.path).readAsStringSync(), example.code);
      expect(entry.readAsStringSync(), 'SELECT 1;');
      expect(
        File(ProjectConfig.configPath(directory.path)).readAsStringSync(),
        config,
      );
    },
  );

  testWidgets(
    'SQL EditorPage connects real unsaved syntax, waves, Problems and owner roots',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'qfli_sql_core_editor_',
      );
      final root = Directory(p.join(directory.path, 'first'))..createSync();
      final second = Directory(p.join(directory.path, 'second'))..createSync();
      const saved = "SELECT 'saved';\r\nSELECT 1;";
      final source = File(p.join(root.path, 'main.sql'))
        ..writeAsStringSync(saved);
      final other = File(p.join(second.path, 'other.sql'))
        ..writeAsStringSync('SELECT 2;');
      final marker = File(p.join(second.path, '.qfli', 'mysql.json'));
      marker.parent.createSync();
      marker.writeAsStringSync('{"schema":"offline_example"}');
      final auth = AuthStore();
      final store = ProjectStore();
      final settings = SettingsStore()..minimap = false;
      final project = Project.create(
        name: 'SQL first',
        path: root.path,
        type: 'sql',
        language: 'SQL',
      );
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        store.dispose();
        settings.dispose();
        // EditorPage flushes its session asynchronously on dispose.
        await _removeTree(tester, directory);
      });
      await tester.pumpWidget(
        _app(
          EditorPage(
            project: project,
            auth: auth,
            store: store,
            settings: settings,
            initialOpenPath: source.path,
          ),
        ),
      );
      await _until(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
      final bar = tester.widget<EditorProblemsBar>(
        find.byType(EditorProblemsBar),
      );
      final analysis = bar.analysis;
      expect(identical(analysis.analyzer, sqlProfile.codeAnalyzer), isTrue);
      await _until(tester, () => analysis.checked && !analysis.pending);
      expect(analysis.unavailableReason, isNull);
      expect(analysis.problems, isEmpty);
      final open = analysis.editor.current!;
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      expect(editor.style!.codeTheme!.language, 'sql');
      final theme = editor.style!.codeTheme!;
      final highlighter = Highlight()
        ..debugMode()
        ..registerLanguages(
          theme.languages.map((name, mode) => MapEntry(name, mode.mode)),
        );
      const dirty = "SELECT '😀';\r\nSELECT 1, FROM;";
      final tokens = _Tokens();
      highlighter
          .highlight(code: dirty, language: theme.language!)
          .render(tokens);
      expect(tokens.parts.map((part) => part.text).join(), dirty);
      expect(
        tokens.parts.any(
          (part) => part.text == 'SELECT' && part.scope == 'keyword',
        ),
        isTrue,
      );
      expect(
        tokens.parts.any(
          (part) => part.text.contains('😀') && part.scope == 'string',
        ),
        isTrue,
      );
      open.controller.text = dirty;
      await _until(
        tester,
        () =>
            analysis.checked &&
            !analysis.pending &&
            analysis.problems.isNotEmpty,
      );
      final problem = analysis.problems.singleWhere(
        (item) =>
            item.source == 'SQLite 引擎' &&
            item.severity == CodeDiagnosticSeverity.error,
      );
      expect(problem.severity, CodeDiagnosticSeverity.error);
      expect(problem.startOffset, dirty.indexOf('FROM'));
      expect(problem.filePath, source.path);
      expect(source.readAsStringSync(), saved);
      expect(open.dirty, isTrue);
      final context = tester.element(find.byType(CodeEditor));
      final decorated = open.controller.buildTextSpan(
        context: context,
        index: 1,
        textSpan: const TextSpan(
          text: 'SELECT 1, FROM;',
          style: TextStyle(color: Colors.blue),
        ),
        style: const TextStyle(),
      );
      final spans = _spanLeaves(decorated);
      expect(decorated.toPlainText(), 'SELECT 1, FROM;');
      expect(
        spans.any(
          (part) => part.style.decorationStyle == TextDecorationStyle.wavy,
        ),
        isTrue,
      );
      expect(spans.every((part) => part.style.color == Colors.blue), isTrue);
      await tester.tap(find.byKey(const ValueKey('editor-problems-status')));
      await tester.pump();
      final panel = find.byType(EditorProblemsPanel);
      expect(panel, findsOneWidget);
      await tester.tap(
        find.descendant(of: panel, matching: find.text(problem.message)),
      );
      await tester.pump();
      expect(open.controller.selection.baseIndex, 1);
      expect(open.controller.selection.baseOffset, 'SELECT 1, '.length);
      expect(analysis.location(problem), 'main.sql:2:11');
      open.controller.text = "SELECT '😀';\r\nSELECT 1;";
      expect(open.diagnostics!.problems, isEmpty);
      await _until(tester, () => analysis.checked && !analysis.pending);
      expect(analysis.problems, isEmpty);
      expect(find.text('本地检查未发现问题'), findsWidgets);
      expect(source.readAsStringSync(), saved);

      // A SQL consumer must follow the selected tab's owner root and dialect.
      expect(
        await tester.runAsync(
          () => analysis.editor.openPath(
            other.path,
            ownerProjectPath: second.path,
            ownerProjectType: 'sql',
            ownerProjectName: 'SQL second',
          ),
        ),
        isNull,
      );
      await _until(
        tester,
        () => !analysis.pending && analysis.unavailableReason != null,
      );
      expect(analysis.unavailableReason, contains('MySQL'));
      expect(analysis.editor.current!.projectRootPath, second.path);
      expect(analysis.problems, isEmpty);
      analysis.editor.current!.controller.text = "SELECT 'open";
      await _until(
        tester,
        () => !analysis.pending && analysis.problems.isNotEmpty,
      );
      expect(
        analysis.problems.every((item) => item.filePath == other.path),
        isTrue,
      );
      expect(open.diagnostics!.problems, isEmpty);
      analysis.editor.select(analysis.editor.files.indexOf(open));
      await _until(tester, () => analysis.checked && !analysis.pending);
      expect(analysis.unavailableReason, isNull);
      expect(analysis.problems, isEmpty);
      expect(source.readAsStringSync(), saved);
      expect(other.readAsStringSync(), 'SELECT 2;');
      expect(tester.takeException(), isNull);
    },
  );
}

MaterialApp _app(Widget home, {double scale = 1}) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('SQL/core operation did not complete');
    }
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

Future<void> _removeTree(WidgetTester tester, Directory directory) async {
  for (var attempt = 0; ; attempt++) {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 49) rethrow;
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }
}

class _Tokens implements HighlightRenderer {
  final parts = <({String text, String? scope})>[];
  final scopes = <String?>[];
  @override
  void addText(String text) =>
      parts.add((text: text, scope: scopes.isEmpty ? null : scopes.last));
  @override
  void openNode(DataNode node) =>
      scopes.add(node.scope ?? (scopes.isEmpty ? null : scopes.last));
  @override
  void closeNode(DataNode node) => scopes.removeLast();
}

List<({String text, TextStyle style})> _spanLeaves(
  TextSpan span, [
  TextStyle inherited = const TextStyle(),
]) {
  final style = inherited.merge(span.style);
  return [
    if (span.text != null) (text: span.text!, style: style),
    for (final child in span.children ?? const <InlineSpan>[])
      if (child is TextSpan) ..._spanLeaves(child, style),
  ];
}
