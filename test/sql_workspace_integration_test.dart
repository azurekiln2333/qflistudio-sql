import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';
// The public editor controller exposes re_editor selection types.
// ignore: depend_on_referenced_packages
import 'package:re_editor/re_editor.dart';

const _runTooltip = '运行（长按运行当前文件）';
const _firstSource = 'src/nested/a.sql';
const _secondSource = 'src/selected.sql';
const _firstCursor = CodeLineSelection.collapsed(index: 2, offset: 3);
const _secondCursor = CodeLineSelection.collapsed(index: 1, offset: 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final library =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(
        Directory.current.path,
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
      );
  late Directory preferences;
  late File preferenceFile;
  late StudioProfile? previousProfile;
  late String? Function() previousToken;
  late SqlEngineKind previousEngine;
  List<int>? previousPreferenceBytes;

  setUpAll(() async {
    previousProfile = StudioProfile.current;
    previousToken = SqlEnginePreference.token;
    preferences = Directory.systemTemp.createTempSync('sql_workspace_prefs_');
    messenger.setMockMethodCallHandler(paths, (_) async => preferences.path);
    final storage = await AppPaths.storageDirectory();
    expect(storage, isNotNull);
    expect(p.equals(storage!, preferences.path), isTrue);
    preferenceFile = File(p.join(storage, 'sql_engine.json'));
    if (preferenceFile.existsSync()) {
      previousPreferenceBytes = preferenceFile.readAsBytesSync();
    }
    previousEngine = await SqlEnginePreference.load();
    StudioProfile.current = sqlProfile;
    SqlEnginePreference.token = () => null;
    await SqlEnginePreference.save(SqlEngineKind.sqlite);
  });

  tearDownAll(() async {
    // Restore the cached selection as well as the exact persisted bytes. A
    // prior cloud selection may only be restored outside the offline profile.
    StudioProfile.current = null;
    await SqlEnginePreference.save(previousEngine);
    if (previousPreferenceBytes case final bytes?) {
      await preferenceFile.writeAsBytes(bytes, flush: true);
    } else if (await preferenceFile.exists()) {
      await preferenceFile.delete();
    }
    SqlEnginePreference.token = previousToken;
    StudioProfile.current = previousProfile;
    messenger.setMockMethodCallHandler(paths, null);
    await preferences.delete(recursive: true);
  });

  group(
    'SQL workspace with the real bundled SQLite engine',
    () {
      testWidgets(
        'drawer reopening and EditorPage reconstruction retain independent roots and owned tabs',
        (tester) async {
          final fixture = await _SqlWorkspaceFixture.createFor(tester);
          await fixture.mount(tester);
          await fixture.joinSecondRoot(tester);
          await fixture.openFirstSource(tester);
          final editor = fixture.editor(tester);
          editor.current!.controller.selection = _firstCursor;
          await tester.pump();
          await fixture.openSecondSource(tester);
          editor.current!.controller.selection = _secondCursor;
          await tester.pump();

          expect(editor.files.map((file) => p.normalize(file.path)), [
            fixture.source(fixture.first, _firstSource).path,
            fixture.source(fixture.second, _secondSource).path,
          ]);
          expect(editor.files.map((file) => file.projectRootPath), [
            fixture.first.path,
            fixture.second.path,
          ]);
          expect(editor.files.map((file) => file.ownerProjectName), [
            fixture.first.name,
            fixture.second.name,
          ]);
          expect(editor.files.map((file) => file.projectType), ['sql', 'sql']);

          await fixture.openDrawer(tester);
          await fixture.expand(tester, fixture.second, 'archive', 'other.sql');
          // Both roots contain src, but only A has nested expanded. Collapsing
          // B's root must preserve its own src/archive state independently.
          await tester.tap(fixture.entry(fixture.second, fixture.second.name));
          await tester.pump();
          expect(fixture.entry(fixture.first, 'a.sql'), findsOneWidget);
          expect(fixture.entry(fixture.second, 'src'), findsNothing);
          await fixture.closeDrawer(tester);
          await fixture.openDrawer(tester);
          await _until(
            tester,
            () =>
                fixture.entry(fixture.first, 'a.sql').evaluate().isNotEmpty &&
                fixture.root(fixture.second).evaluate().isNotEmpty &&
                fixture.entry(fixture.second, 'src').evaluate().isEmpty &&
                fixture.rootCollapsed(fixture.second).evaluate().isNotEmpty,
            operation: 'restore expanded A and collapsed B after drawer reopen',
          );
          expect(fixture.entry(fixture.first, 'a.sql'), findsOneWidget);
          expect(fixture.root(fixture.second), findsOneWidget);
          expect(fixture.entry(fixture.second, 'src'), findsNothing);
          expect(editor.current!.projectRootPath, fixture.second.path);
          _expectCursor(editor.current!.controller.selection, _secondCursor);

          await fixture.unmount(tester);
          final workspace = await fixture.savedWorkspace(tester);
          final session = workspace.session;
          expect(
            workspace.memberPaths,
            unorderedEquals([fixture.first.path, fixture.second.path]),
          );
          expect(session.primaryPath, fixture.first.path);
          expect(
            session.expandedDirs[fixture.first.path],
            unorderedEquals(['src', 'src/nested']),
          );
          expect(session.rootExpanded[fixture.first.path], isTrue);
          expect(
            session.expandedDirs[fixture.second.path],
            unorderedEquals(['src', 'src/archive']),
          );
          expect(session.rootExpanded[fixture.second.path], isFalse);
          expect(
            session.documents.map((document) => document.relativePath),
            [_firstSource, _secondSource],
          );
          expect(
            session.documents.map((document) => document.projectPath),
            [fixture.first.path, fixture.second.path],
          );
          expect(session.documents.map((document) => document.isActive), [
            false,
            true,
          ]);
          expect(
            session.documents.first.cursor.baseIndex,
            _firstCursor.baseIndex,
          );
          expect(
            session.documents.first.cursor.baseOffset,
            _firstCursor.baseOffset,
          );
          expect(
            session.documents.last.cursor.extentIndex,
            _secondCursor.extentIndex,
          );
          expect(
            session.documents.last.cursor.extentOffset,
            _secondCursor.extentOffset,
          );
          await fixture.expectStandaloneHistoriesUnchanged(tester);

          await fixture.mount(tester, expectedFiles: 2);
          final restored = fixture.editor(tester);
          expect(restored, isNot(same(editor)));
          expect(restored.files.map((file) => p.normalize(file.path)), [
            fixture.source(fixture.first, _firstSource).path,
            fixture.source(fixture.second, _secondSource).path,
          ]);
          expect(restored.files.map((file) => file.projectRootPath), [
            fixture.first.path,
            fixture.second.path,
          ]);
          expect(restored.files.map((file) => file.ownerProjectName), [
            fixture.first.name,
            fixture.second.name,
          ]);
          expect(restored.files.every((file) => !file.dirty), isTrue);
          expect(restored.currentIndex, 1);
          expect(restored.current!.projectRootPath, fixture.second.path);
          _expectCursor(
            restored.files.first.controller.selection,
            _firstCursor,
          );
          _expectCursor(restored.current!.controller.selection, _secondCursor);
          await fixture.openDrawer(tester);
          await _until(
            tester,
            () =>
                fixture.entry(fixture.first, 'a.sql').evaluate().isNotEmpty &&
                fixture.root(fixture.second).evaluate().isNotEmpty &&
                fixture.entry(fixture.second, 'src').evaluate().isEmpty &&
                fixture.rootCollapsed(fixture.second).evaluate().isNotEmpty,
          );
          expect(fixture.entry(fixture.first, 'a.sql'), findsOneWidget);
          expect(fixture.entry(fixture.second, 'src'), findsNothing);
          await tester.tap(fixture.entry(fixture.second, fixture.second.name));
          await _until(
            tester,
            () => fixture
                .entry(fixture.second, 'other.sql')
                .evaluate()
                .isNotEmpty,
          );
          expect(fixture.entry(fixture.second, 'selected.sql'), findsOneWidget);
          expect(fixture.entry(fixture.first, 'a.sql'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'tap and long press run the active SQL owner without saving another root',
        (tester) async {
          final fixture = await _SqlWorkspaceFixture.createFor(tester);
          await fixture.mount(tester);
          await fixture.joinSecondRoot(tester);
          await fixture.openFirstSource(tester);
          final editor = fixture.editor(tester);
          final primary = editor.current!;
          final originalPrimary = fixture
              .source(fixture.first, _firstSource)
              .readAsStringSync();
          const dirtyPrimary =
              "-- keep A unsaved while B runs\nINSERT INTO runs(tag) VALUES ('A-selected-dirty');\nSELECT tag FROM runs;\n";
          primary.controller.text = dirtyPrimary;
          await tester.pump();
          await fixture.openSecondSource(tester);
          final secondary = editor.current!;
          const savedBeforeEntry =
              "-- B is saved before its configured entry runs\nINSERT INTO runs(tag) VALUES ('B-selected-from-tap');\nSELECT tag FROM runs;\n";
          secondary.controller.text = savedBeforeEntry;
          await tester.pump();
          final firstConfig = File(
            ProjectConfig.configPath(fixture.first.path),
          ).readAsStringSync();
          final secondConfig = File(
            ProjectConfig.configPath(fixture.second.path),
          ).readAsStringSync();

          expect(identical(StudioProfile.current, sqlProfile), isTrue);
          expect(
            identical(StudioProfile.current!.runner, sqlProfile.runner),
            isTrue,
          );
          expect(
            await tester.runAsync(SqlEnginePreference.load),
            SqlEngineKind.sqlite,
          );
          await tester.tap(find.byTooltip(_runTooltip));
          await fixture.waitForRows(tester, fixture.second, ['B-entry']);
          expect(
            await tester.runAsync(() => fixture.rows(fixture.first)),
            isEmpty,
          );
          expect(
            fixture.source(fixture.second, _secondSource).readAsStringSync(),
            savedBeforeEntry,
          );
          expect(secondary.dirty, isFalse);
          expect(primary.dirty, isTrue);
          expect(primary.controller.text, dirtyPrimary);
          expect(
            fixture.source(fixture.first, _firstSource).readAsStringSync(),
            originalPrimary,
          );

          const currentFileRun =
              "-- long press saves and runs this B file\nINSERT INTO runs(tag) VALUES ('B-selected-longpress');\nSELECT tag FROM runs;\n";
          secondary.controller.text = currentFileRun;
          await tester.pump();
          await tester.longPress(find.byTooltip(_runTooltip));
          await fixture.waitForRows(tester, fixture.second, [
            'B-entry',
            'B-selected-longpress',
          ]);
          expect(
            await tester.runAsync(() => fixture.rows(fixture.first)),
            isEmpty,
          );
          expect(
            fixture.source(fixture.second, _secondSource).readAsStringSync(),
            currentFileRun,
          );
          expect(secondary.dirty, isFalse);
          expect(primary.dirty, isTrue);
          expect(
            fixture.source(fixture.first, _firstSource).readAsStringSync(),
            originalPrimary,
          );

          final primaryTab = find.descendant(
            of: find.byType(TabBar),
            matching: find.text(primary.tabLabel(fixture.first.name)),
          );
          await tester.ensureVisible(primaryTab);
          await tester.tap(primaryTab);
          await _until(tester, () => identical(editor.current, primary));
          await tester.tap(find.byTooltip(_runTooltip));
          await fixture.waitForRows(tester, fixture.first, ['A-entry']);
          expect(await tester.runAsync(() => fixture.rows(fixture.second)), [
            'B-entry',
            'B-selected-longpress',
          ]);
          expect(primary.dirty, isFalse);
          expect(
            fixture.source(fixture.first, _firstSource).readAsStringSync(),
            dirtyPrimary,
          );
          expect(
            File(
              ProjectConfig.configPath(fixture.first.path),
            ).readAsStringSync(),
            firstConfig,
          );
          expect(
            File(
              ProjectConfig.configPath(fixture.second.path),
            ).readAsStringSync(),
            secondConfig,
          );
          for (final owner in [fixture.first, fixture.second]) {
            expect(fixture.databaseFile(owner).existsSync(), isTrue);
            expect(
              fixture.source(owner, 'src/.qfli/data.sqlite').existsSync(),
              isFalse,
            );
            expect(
              fixture.source(owner, '.qfli/mysql.json').existsSync(),
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    },
    skip: !File(library).existsSync()
        ? 'Bundled SQLite library unavailable; SQL workspace host gate not run'
        : false,
  );
}

class _SqlWorkspaceFixture {
  _SqlWorkspaceFixture(this.directory, this.store, this.first, this.second)
    : settings = SettingsStore(
        storageFile: File(p.join(directory.path, 'settings.json')),
      )..minimap = false,
      workspaceStore = WorkspaceStore(
        root: Directory(p.join(directory.path, 'workspaces')),
      );

  final Directory directory;
  final ProjectStore store;
  final Project first;
  final Project second;
  final AuthStore auth = AuthStore();
  final SettingsStore settings;
  final WorkspaceStore workspaceStore;
  final NativeSqliteDatabase database = const NativeSqliteDatabase();
  SavedWorkspace? _workspace;
  Map<String, List<int>?>? _standaloneHistoryBytes;
  bool _disposed = false;

  static Future<_SqlWorkspaceFixture> createFor(WidgetTester tester) async {
    final fixture = await tester.runAsync(_create);
    expect(fixture, isNotNull);
    tester.view.physicalSize = const Size(680, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      try {
        await fixture!.dispose(tester);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
    return fixture!;
  }

  static Future<_SqlWorkspaceFixture> _create() async {
    final directory = await Directory.systemTemp.createTemp(
      'qfli_sql_workspace_',
    );
    final store = ProjectStore(
      storageFile: File(p.join(directory.path, 'projects.json')),
    );
    _SqlWorkspaceFixture? fixture;
    try {
      for (final name in ['A', 'B']) {
        final root = Directory(p.join(directory.path, name));
        await Directory(
          p.join(root.path, 'src', name == 'A' ? 'nested' : 'archive'),
        ).create(recursive: true);
        await ProjectConfig.write(
          projectRoot: root.path,
          name: 'SQL $name',
          language: 'SQL',
          type: 'sql',
          entryFile: name == 'A' ? 'main.sql' : 'src/entry.sql',
          strict: true,
        );
        await File(
          p.join(root.path, name == 'A' ? 'main.sql' : 'src/entry.sql'),
        ).writeAsString("INSERT INTO runs(tag) VALUES ('$name-entry');\n");
        await File(
          p.join(root.path, name == 'A' ? _firstSource : _secondSource),
        ).writeAsString(
          "-- $name selected file\nINSERT INTO runs(tag) VALUES ('$name-selected-saved');\nSELECT tag FROM runs;\n",
        );
        if (name == 'B') {
          await File(
            p.join(root.path, 'src/archive/other.sql'),
          ).writeAsString('SELECT 2;\n');
        }
      }
      await store.load();
      final first = await store.addExisting(p.join(directory.path, 'A'));
      final second = await store.addExisting(p.join(directory.path, 'B'));
      expect(first.error, isNull);
      expect(second.error, isNull);
      fixture = _SqlWorkspaceFixture(
        directory,
        store,
        first.project!,
        second.project!,
      );
      for (final owner in [fixture.first, fixture.second]) {
        final identity = await fixture.database.query(
          databasePath: fixture.databaseFile(owner).path,
          source: 'SELECT sqlite_version() AS version;',
        );
        expect(identity.success, isTrue, reason: identity.error);
        expect(identity.rows, [
          ['3.50.0'],
        ]);
        final schema = await fixture.database.executeScript(
          databasePath: fixture.databaseFile(owner).path,
          source:
              'CREATE TABLE runs (seq INTEGER PRIMARY KEY, tag TEXT NOT NULL);',
        );
        expect(schema.success, isTrue, reason: schema.error);
      }
      return fixture;
    } catch (_) {
      fixture?.auth.dispose();
      fixture?.settings.dispose();
      fixture?.workspaceStore.dispose();
      store.dispose();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  File source(Project owner, String relativePath) =>
      File(p.normalize(p.join(owner.path, relativePath)));
  File databaseFile(Project owner) => source(owner, '.qfli/data.sqlite');
  Finder root(Project owner) =>
      find.byKey(ValueKey('workspace-root-${owner.path}'));
  Finder entry(Project owner, String name) =>
      find.descendant(of: root(owner), matching: find.text(name));
  Finder rootCollapsed(Project owner) => find.descendant(
    of: find.ancestor(
      of: entry(owner, owner.name),
      matching: find.byType(InkWell),
    ).first,
    matching: find.byIcon(Icons.keyboard_arrow_right),
  );
  EditorController editor(WidgetTester tester) => tester
      .widget<EditorProblemsBar>(find.byType(EditorProblemsBar))
      .analysis
      .editor;

  Future<void> mount(WidgetTester tester, {int expectedFiles = 0}) async {
    final workspace = _workspace == null ? null : await savedWorkspace(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          project: first,
          auth: auth,
          store: store,
          settings: settings,
          workspace: workspace,
          workspaceMembers: workspace == null ? const [] : [first, second],
          workspaceStore: workspaceStore,
        ),
      ),
    );
    // The empty editor intentionally has no code view/Problems bar. Wait for
    // its actual UI before opening the first file through the tree.
    await _until(
      tester,
      () => expectedFiles == 0
          ? find.text('在左侧选择要编辑的文件').evaluate().isNotEmpty &&
                find.byTooltip('打开文件树').evaluate().isNotEmpty
          : find.byType(EditorProblemsBar).evaluate().isNotEmpty &&
                editor(tester).files.length == expectedFiles,
      operation: 'mount SQL editor with $expectedFiles files',
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('打开文件树'));
    await tester.pumpAndSettle();
    await _until(
      tester,
      () => root(first).evaluate().isNotEmpty,
      operation: 'open compact drawer for ${first.path}',
    );
  }

  Future<void> closeDrawer(WidgetTester tester) async {
    await tester.tapAt(const Offset(650, 650));
    await tester.pumpAndSettle();
    expect(root(first), findsNothing);
  }

  Future<void> joinSecondRoot(WidgetTester tester) async {
    await openDrawer(tester);
    await _until(
      tester,
      () => entry(first, 'src').evaluate().isNotEmpty,
      operation: 'load ${first.path}/src before selecting workspace roots',
    );
    await tester.tap(find.byTooltip('工作区项目'));
    await tester.pumpAndSettle();
    // The dialog awaits WorkspaceStore.load() (real directory IO) before
    // showDialog. A settle-only pump can outrun that future, so wait for the
    // dialog's actual name field and the second-root choice before reading it.
    final choice = find.byKey(ValueKey('workspace-project-${second.id}'));
    await _until(
      tester,
      () =>
          find
              .byKey(const ValueKey('workspace-name-field'))
              .evaluate()
              .isNotEmpty &&
          choice.evaluate().isNotEmpty,
      operation: 'open workspace dialog and list ${second.path}',
    );
    expect(tester.widget<CheckboxListTile>(choice).value, isFalse);
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.enterText(
      find.byKey(const ValueKey('workspace-name-field')),
      'SQL owner workspace',
    );
    // Empty-session restoration also schedules a 1500 ms history save. Let
    // that outgoing standalone timer fire, then fence its queued write before
    // promotion. Named actions must never replace either history file.
    await tester.pump(const Duration(milliseconds: 1600));
    for (final owner in [first, second]) {
      await history(tester, owner);
    }
    _standaloneHistoryBytes = {
      for (final owner in [first, second])
        owner.path: _historyBytes(owner),
    };
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await _until(
      tester,
      () => entry(second, 'src').evaluate().isNotEmpty,
      operation: 'join workspace root ${second.path}',
    );
    expect(workspaceStore.workspaces, hasLength(1));
    _workspace = workspaceStore.workspaces.single;
    expect(_workspace!.name, 'SQL owner workspace');
    expect(
      _workspace!.memberPaths,
      unorderedEquals([first.path, second.path]),
    );
    await expectStandaloneHistoriesUnchanged(tester);
  }

  Future<void> expand(
    WidgetTester tester,
    Project owner,
    String folder,
    String child,
  ) async {
    await _until(
      tester,
      () => entry(owner, folder).evaluate().isNotEmpty,
      operation: 'find folder $folder in ${owner.path}',
    );
    await tester.ensureVisible(entry(owner, folder));
    await tester.tap(entry(owner, folder));
    await _until(
      tester,
      () => entry(owner, child).evaluate().isNotEmpty,
      operation: 'expand ${owner.path}/$folder to expose $child',
    );
  }

  Future<void> openFirstSource(WidgetTester tester) async {
    await expand(tester, first, 'src', 'nested');
    await expand(tester, first, 'nested', 'a.sql');
    await tester.tap(entry(first, 'a.sql'));
    await _until(
      tester,
      () =>
          find.byType(EditorProblemsBar).evaluate().isNotEmpty &&
          p.equals(
            editor(tester).current?.path ?? '',
            source(first, _firstSource).path,
          ),
      operation: 'open primary SQL source ${source(first, _firstSource).path}',
    );
    await tester.pumpAndSettle();
    expect(root(first), findsNothing);
  }

  Future<void> openSecondSource(WidgetTester tester) async {
    await openDrawer(tester);
    await expand(tester, second, 'src', 'selected.sql');
    await tester.ensureVisible(entry(second, 'selected.sql'));
    await tester.tap(entry(second, 'selected.sql'));
    await _until(
      tester,
      () =>
          find.byType(EditorProblemsBar).evaluate().isNotEmpty &&
          p.equals(
            editor(tester).current?.path ?? '',
            source(second, _secondSource).path,
          ),
      operation:
          'open secondary SQL source ${source(second, _secondSource).path}',
    );
    await tester.pumpAndSettle();
    expect(root(first), findsNothing);
  }

  Future<ProjectSession> history(WidgetTester tester, Project owner) async {
    ProjectSession? saved;
    ProjectHistory.load(owner.path).then((value) => saved = value);
    await _until(
      tester,
      () => saved != null,
      operation: 'drain persisted history for ${owner.path}',
    );
    return saved!;
  }

  List<int>? _historyBytes(Project owner) {
    final file = ProjectHistory.historyFile(owner.path);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  Future<void> expectStandaloneHistoriesUnchanged(WidgetTester tester) async {
    final before = _standaloneHistoryBytes;
    expect(before, isNotNull);
    for (final owner in [first, second]) {
      await history(tester, owner);
      expect(
        _historyBytes(owner),
        before![owner.path],
        reason: 'Named workspace changed standalone history for ${owner.path}',
      );
    }
  }

  Future<void> _settleWorkspace(WidgetTester tester) async {
    var settled = false;
    workspaceStore.settle().then((_) => settled = true);
    await _until(
      tester,
      () => settled,
      operation: 'drain named workspace session writes',
    );
  }

  Future<SavedWorkspace> savedWorkspace(WidgetTester tester) async {
    await _settleWorkspace(tester);
    var reloaded = false;
    workspaceStore.load(force: true).then((_) => reloaded = true);
    await _until(
      tester,
      () => reloaded,
      operation: 'reload persisted named workspace session',
    );
    final saved = workspaceStore.byId(_workspace!.id);
    expect(saved, isNotNull);
    final persisted = saved!;
    _workspace = persisted;
    return persisted;
  }

  Future<List<String>> rows(Project owner) async {
    final result = await database.query(
      databasePath: databaseFile(owner).path,
      source: 'SELECT tag FROM runs ORDER BY seq;',
    );
    expect(result.success, isTrue, reason: result.error);
    expect(result.truncated, isFalse);
    return [for (final row in result.rows) row.single!];
  }

  Future<void> waitForRows(
    WidgetTester tester,
    Project owner,
    List<String> expected,
  ) async {
    List<String> actual = const [];
    for (var attempt = 0; attempt < 200; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      actual = (await tester.runAsync(() => rows(owner)))!;
      await tester.pump();
      final panes = find.byType(TerminalPane);
      if (actual.join('\n') == expected.join('\n') &&
          panes.evaluate().isNotEmpty &&
          !tester.state<TerminalPaneState>(panes).busy) {
        expect(actual, expected);
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(
      actual,
      expected,
      reason:
          'Real SQL owner run did not complete for ${owner.path}.\n'
          '${_workspaceDiagnostics(tester)}',
    );
    fail(
      'The SQL terminal remained busy after committing the expected rows.\n'
      '${_workspaceDiagnostics(tester)}',
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    await unmount(tester);
    await _settleWorkspace(tester);
    if (_workspace != null) {
      await savedWorkspace(tester);
      await expectStandaloneHistoriesUnchanged(tester);
    }
    // load is the real ProjectHistory write-queue fence. Alternate fake and
    // real event loops so disposal cannot delete a root while history is open.
    await history(tester, first);
    await history(tester, second);
    var registrySettled = false;
    store.refresh().then((_) => registrySettled = true);
    await _until(
      tester,
      () => registrySettled,
      operation: 'drain project registry before removing fixture roots',
    );
    auth.dispose();
    settings.dispose();
    workspaceStore.dispose();
    store.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}

void _expectCursor(CodeLineSelection actual, CodeLineSelection expected) {
  expect(actual.baseIndex, expected.baseIndex);
  expect(actual.baseOffset, expected.baseOffset);
  expect(actual.extentIndex, expected.extentIndex);
  expect(actual.extentOffset, expected.extentOffset);
}

String _workspaceDiagnostics(WidgetTester tester) {
  final bars = find.byType(EditorProblemsBar, skipOffstage: false);
  final editors = <EditorController>{
    for (final bar in tester.widgetList<EditorProblemsBar>(bars))
      bar.analysis.editor,
  };
  return [
    'Problems bars: visible=${find.byType(EditorProblemsBar).evaluate().length}, '
        'all=${bars.evaluate().length}; '
        'code views=${find.byType(CodeEditor).evaluate().length}; '
        'drawers=${find.byType(Drawer).evaluate().length}',
    for (final editor in editors)
      'editor: currentIndex=${editor.currentIndex}; '
          'currentPath=${editor.current?.path}; '
          'currentOwner=${editor.current?.projectRootPath}; '
          'files=${editor.files.map((file) => '${file.path} '
              '(owner=${file.projectRootPath}, dirty=${file.dirty})').toList()}',
  ].join('\n');
}

Future<void> _until(
  WidgetTester tester,
  bool Function() complete, {
  String operation = 'SQL workspace IO',
}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (complete()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    complete(),
    isTrue,
    reason: '$operation did not finish.\n${_workspaceDiagnostics(tester)}',
  );
}
