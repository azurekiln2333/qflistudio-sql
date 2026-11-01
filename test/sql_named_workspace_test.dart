import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/sql_app.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_home_shell.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/editor/project_history.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';
// Inspect the production editor's actual cursor state.
// ignore: depend_on_referenced_packages
import 'package:re_editor/re_editor.dart';

const _workspaceName = 'SQL local workbench';
const _firstSource = '-- First SQL\nSELECT 1 AS value;\nSELECT 2 AS other;\n';
const _secondSource = '-- Second SQL\nSELECT 3 AS value;\nSELECT 4 AS other;\n';
const _firstCursor = CodeLineSelection.collapsed(index: 1, offset: 7);
const _secondCursor = CodeLineSelection.collapsed(index: 2, offset: 9);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final library = Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(Directory.current.path, 'native', 'build',
          Platform.operatingSystem,
          Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so');
  late _SqlNamedFixture fixture;
  late File preference;
  late SqlEngineKind previousEngine;
  StudioProfile? previousProfile;
  late String? Function() previousToken;
  List<int>? previousPreference;

  setUpAll(() async {
    fixture = await _SqlNamedFixture.create();
    messenger.setMockMethodCallHandler(paths, (_) async => fixture.directory.path);
    expect(await AppPaths.storageDirectory(), fixture.directory.path);
    preference = File(p.join(fixture.directory.path, 'sql_engine.json'));
    if (preference.existsSync()) {
      previousPreference = preference.readAsBytesSync();
    }
    previousEngine = await SqlEnginePreference.load();
    previousProfile = StudioProfile.current;
    previousToken = SqlEnginePreference.token;
    StudioProfile.current = sqlProfile;
    SqlEnginePreference.token = () => null;
    await SqlEnginePreference.save(SqlEngineKind.sqlite);
    await WorkspaceStore.instance.load();
  });
  tearDownAll(() async {
    StudioProfile.current = null;
    await SqlEnginePreference.save(previousEngine);
    if (previousPreference case final bytes?) {
      await preference.writeAsBytes(bytes, flush: true);
    } else if (await preference.exists()) {
      await preference.delete();
    }
    SqlEnginePreference.token = previousToken;
    StudioProfile.current = previousProfile;
    messenger.setMockMethodCallHandler(paths, null);
    fixture.disposeStores();
    fixture.ready.dispose();
    await fixture.directory.delete(recursive: true);
  });

  group('SQL named workspaces with the actual bundled SQLite engine', () {
  testWidgets(
    'actual SQL shell saves and reopens a named two-root session without overwriting standalone histories',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      binding.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(binding.platformDispatcher.clearLocaleTestValue);
      addTearDown(() => fixture.unmountAndDrain(tester));
      expect(StudioProfile.current, same(sqlProfile));
      expect(sqlProfile.productKey, StudioProductCatalog.sqlabKey);
      expect(sqlProfile.offlineOnly, isTrue);
      expect(sqlProfile.supportsSavedWorkspaces, isTrue);
      expect(isMainStudioRelease, isFalse);
      final identity = await tester.runAsync(() =>
          const NativeSqliteDatabase().query(
            databasePath: ':memory:', source: 'SELECT sqlite_version();'));
      expect(identity!.success, isTrue, reason: identity.error);
      expect(identity.rows, [['3.50.0']]);

      await fixture.mount(tester);
      await fixture.openProjects(tester);
      expect(find.text('云端项目'), findsNothing);
      await tester.tap(find.text(fixture.first.name).hitTestable());
      await _until(tester, () => fixture.editor(tester)?.files.length == 1,
          'open the real SQL project');
      await fixture.showTree(tester);
      // Fence the standalone editor's genuine 1500ms debounce before named
      // promotion. Queue drains alone cannot observe a timer not yet fired.
      await tester.pump(const Duration(milliseconds: 1600));
      await fixture.drain(tester);
      final legacyBytes = {
        for (final owner in fixture.projects)
          owner.path: fixture.history(owner).readAsBytesSync(),
      };

      final action = find.descendant(
        of: find.byType(FileExplorer),
        matching: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '工作区项目'),
      ).hitTestable();
      await tester.tap(action);
      final name = find.byKey(const ValueKey('workspace-name-field'));
      await _until(tester, () => name.hitTestable().evaluate().isNotEmpty,
          'show the named workspace dialog for sqlProfile');
      final member = find.byKey(ValueKey('workspace-project-${fixture.second.id}'));
      expect(tester.widget<CheckboxListTile>(member).value, isFalse);
      await tester.ensureVisible(member);
      await _until(tester, () => member.hitTestable().evaluate().isNotEmpty,
          'show the second SQL workspace member');
      await tester.tap(member);
      await tester.enterText(name, _workspaceName);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await _until(tester,
          () => WorkspaceStore.instance.workspaces.length == 1 &&
              find.byType(AlertDialog).evaluate().isEmpty &&
              fixture.root(fixture.second).evaluate().isNotEmpty,
          'save both SQL project roots');
      final saved = WorkspaceStore.instance.workspaces.single;
      await _until(tester,
          () => fixture.page(tester).workspace?.id == saved.id,
          'promote the actual SQL retained editor to named mode');
      expect(saved.name, _workspaceName);
      expect(saved.memberPaths, fixture.projects.map((owner) => owner.path));
      expect(File(p.join(fixture.directory.path, 'workspaces', '${saved.id}.json'))
          .existsSync(), isTrue);

      for (final owner in fixture.projects) {
        await _until(tester,
            () => fixture.entry(owner, 'nested')
                .hitTestable().evaluate().isNotEmpty,
            'load ${owner.name} nested folder');
        await tester.tap(fixture.entry(owner, 'nested'));
        await _until(tester,
            () => fixture.entry(owner, 'detail.sql').evaluate().isNotEmpty,
            'expand ${owner.name} independently');
      }
      await _until(tester,
          () => fixture.entry(fixture.second, 'main.sql')
              .hitTestable().evaluate().isNotEmpty,
          'show the second SQL source row');
      await tester.tap(fixture.entry(fixture.second, 'main.sql'));
      await _until(tester,
          () => fixture.editor(tester)?.files.length == 2 &&
              fixture.editor(tester)?.current?.projectRootPath == fixture.second.path,
          'open second SQL source with its actual owner');
      final editor = fixture.editor(tester)!;
      expect(editor.files.map((file) => p.normalize(file.path)),
          fixture.projects.map((owner) => fixture.source(owner).path));
      expect(editor.files.map((file) => file.projectRootPath),
          fixture.projects.map((owner) => owner.path));
      expect(editor.files.every((file) => file.projectType == 'sql'), isTrue);
      await tester.tap(fixture.entry(fixture.second, fixture.second.name));
      await _until(tester, () => fixture.restoredTree,
          'collapse only the second root');
      editor.files.first.controller.text = '-- First dirty\nSELECT 10;\nSELECT 20;\n';
      editor.files.last.controller.text = '-- Second dirty\nSELECT 30;\nSELECT 40;\n';
      await tester.pump();
      expect(editor.files.every((file) => file.dirty), isTrue);
      await tester.tap(find.byTooltip('收起文件树').hitTestable());
      await tester.pump(const Duration(milliseconds: 300));
      await fixture.showTree(tester);
      await _until(tester, () => fixture.restoredTree,
          'restore independent expansion after SQL sidebar reopen');
      expect(fixture.editor(tester), same(editor));

      await tester.tap(find.byTooltip('暂时收起编辑器').hitTestable());
      await _until(tester,
          () => find.byTooltip('已保存的工作区').hitTestable().evaluate().isNotEmpty,
          'return to SQL projects while preserving the live named session');
      await fixture.openSaved(tester);
      await _until(tester, () => identical(fixture.editor(tester), editor),
          'resume the named session through the SQL saved-workspace action');
      expect(editor.files.first.controller.text,
          '-- First dirty\nSELECT 10;\nSELECT 20;\n');
      expect(editor.files.last.controller.text,
          '-- Second dirty\nSELECT 30;\nSELECT 40;\n');
      expect(editor.files.every((file) => file.dirty), isTrue);
      fixture.expectSourceBytes();

      // Session metadata deliberately does not persist unsaved source. Restore
      // clean text in memory before the separate app-reconstruction check.
      editor.files.first.controller.text = _firstSource;
      editor.files.last.controller.text = _secondSource;
      editor.files.first.controller.selection = _firstCursor;
      editor.files.last.controller.selection = _secondCursor;
      await tester.pump(const Duration(milliseconds: 1600));
      await fixture.drain(tester);
      fixture.expectHistoryBytes(legacyBytes);
      await fixture.unmountAndDrain(tester);
      final latest = WorkspaceStore.instance.byId(saved.id)!;
      expect(latest.session.documents.map((document) => document.projectPath),
          fixture.projects.map((owner) => owner.path));
      expect(latest.session.documents.map((document) => document.relativePath),
          ['main.sql', 'main.sql']);
      expect(latest.session.documents.map((document) => document.isActive),
          [false, true]);
      expect(latest.session.documents.first.cursor.toJson(),
          _fileCursor(_firstCursor).toJson());
      expect(latest.session.documents.last.cursor.toJson(),
          _fileCursor(_secondCursor).toJson());
      for (final owner in fixture.projects) {
        expect(latest.session.expandedDirs[owner.path], contains('nested'));
      }
      expect(latest.session.rootExpanded[fixture.first.path], isTrue);
      expect(latest.session.rootExpanded[fixture.second.path], isFalse);
      fixture.expectHistoryBytes(legacyBytes);
      fixture.expectSourceBytes();

      await tester.runAsync(() async {
        await WorkspaceStore.instance.load(force: true);
        await fixture.recreateStores();
      });
      await fixture.mount(tester);
      await fixture.openProjects(tester);
      await fixture.openSaved(tester);
      await _until(tester, () => fixture.editor(tester)?.files.length == 2,
          'reconstruct SQL named documents from persisted workspace');
      final restored = fixture.editor(tester)!;
      expect(restored, isNot(same(editor)));
      expect(fixture.page(tester).workspace?.id, saved.id);
      expect(restored.files.map((file) => p.normalize(file.path)),
          fixture.projects.map((owner) => fixture.source(owner).path));
      expect(restored.files.map((file) => file.projectRootPath),
          fixture.projects.map((owner) => owner.path));
      expect(restored.files.map((file) => file.ownerProjectName),
          fixture.projects.map((owner) => owner.name));
      expect(restored.current?.projectRootPath, fixture.second.path);
      expect(restored.files.first.controller.text, _firstSource);
      expect(restored.files.last.controller.text, _secondSource);
      _expectCursor(restored.files.first.controller.selection, _firstCursor);
      _expectCursor(restored.files.last.controller.selection, _secondCursor);
      await fixture.showTree(tester);
      await _until(tester, () => fixture.restoredTree,
          'restore both root expansion states after whole-app reconstruction');
      await _until(tester,
          () => fixture.entry(fixture.second, fixture.second.name)
              .hitTestable().evaluate().isNotEmpty,
          'show the second SQL root row before expanding it');
      await tester.tap(fixture.entry(fixture.second, fixture.second.name));
      await _until(tester,
          () => fixture.entry(fixture.second, 'detail.sql').evaluate().isNotEmpty,
          'recover nested expansion when the second root is expanded again');
      fixture.expectHistoryBytes(legacyBytes);
      fixture.expectSourceBytes();
      expect(StudioProfile.current, same(sqlProfile));
      expect(tester.takeException(), isNull);
    },
  );
  }, skip: !File(library).existsSync()
        ? 'Bundled SQLite unavailable; actual SQL named-workspace gate not run'
        : false,
  );
}

class _SqlNamedFixture {
  _SqlNamedFixture(this.directory, this.first, this.second);
  final Directory directory;
  final Project first;
  final Project second;
  final ready = ValueNotifier(true);
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  List<Project> get projects => [first, second];
  File get registry => File(p.join(directory.path, 'projects.json'));
  File source(Project owner) => File(p.join(owner.path, 'main.sql'));
  File history(Project owner) => File(p.join(owner.path, 'history.json'));
  Finder root(Project owner) => find.byKey(ValueKey('workspace-root-${owner.path}'));
  Finder entry(Project owner, String name) =>
      find.descendant(of: root(owner), matching: find.text(name));
  bool get restoredTree =>
      entry(first, 'detail.sql').hitTestable().evaluate().isNotEmpty &&
      root(second).hitTestable().evaluate().isNotEmpty &&
      entry(second, second.name).hitTestable().evaluate().isNotEmpty &&
      entry(second, 'nested').evaluate().isEmpty &&
      find.descendant(
        of: find.ancestor(of: entry(second, second.name),
            matching: find.byType(InkWell)).first,
        matching: find.byIcon(Icons.keyboard_arrow_right),
      ).hitTestable().evaluate().isNotEmpty;

  static Future<_SqlNamedFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('sql_named_workspace_');
    final store = ProjectStore(storageFile: File(p.join(directory.path, 'projects.json')));
    await store.load();
    final owners = <Project>[];
    for (final name in ['First SQL', 'Second SQL']) {
      final root = Directory(p.join(directory.path, name));
      await Directory(p.join(root.path, 'nested')).create(recursive: true);
      await ProjectConfig.write(projectRoot: root.path, name: name,
          language: 'SQL', type: 'sql', entryFile: 'main.sql', strict: true);
      await File(p.join(root.path, 'main.sql')).writeAsString(
          owners.isEmpty ? _firstSource : _secondSource);
      await File(p.join(root.path, 'nested', 'detail.sql'))
          .writeAsString('SELECT 5 AS detail;\n');
      final added = await store.addExisting(root.path);
      expect(added.error, isNull);
      final project = added.project!;
      owners.add(project);
      // These are pre-existing standalone histories, not the expected final
      // workspace document. The named session is created only by real UI.
      await ProjectHistory.save(project.path, cursors: const {},
          openFiles: const ['main.sql'], activeFile: 'main.sql');
    }
    store.dispose();
    final fixture = _SqlNamedFixture(directory, owners.first, owners.last);
    await fixture._createStores();
    return fixture;
  }

  Future<void> _createStores() async {
    store = ProjectStore(storageFile: registry);
    auth = AuthStore();
    settings = SettingsStore(storageFile: File(p.join(directory.path, 'settings.json')))
      ..minimap = false;
    await store.load();
  }
  Future<void> recreateStores() async {
    disposeStores();
    await _createStores();
  }
  void disposeStores() {
    store.dispose();
    auth.dispose();
    settings.dispose();
  }
  EditorController? editor(WidgetTester tester) {
    final bars = find.byType(EditorProblemsBar).hitTestable();
    return bars.evaluate().isEmpty ? null :
        tester.widget<EditorProblemsBar>(bars).analysis.editor;
  }
  EditorPage page(WidgetTester tester) =>
      tester.widget<EditorPage>(find.byType(EditorPage));
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(SqlLabApp(store: store, auth: auth,
        settings: settings, ready: ready));
    await _until(tester, () => find.byType(SqlHomeShell).evaluate().isNotEmpty,
        'mount the actual SQL app shell');
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
        hasLength(5));
  }
  Future<void> openProjects(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byType(NavigationRail),
        matching: find.text('项目')).hitTestable());
    await _until(tester, () => find.text(first.name).hitTestable().evaluate().isNotEmpty,
        'show SQL projects destination');
  }
  Future<void> openSaved(WidgetTester tester) async {
    await tester.tap(find.byTooltip('已保存的工作区').hitTestable());
    await _until(tester,
        () => find.text(_workspaceName).hitTestable().evaluate().isNotEmpty,
        'show SQL saved-workspace card');
    expect(find.widgetWithText(AppBar, '工作区'), findsOneWidget);
    await tester.tap(find.text(_workspaceName).hitTestable());
  }
  Future<void> showTree(WidgetTester tester) async {
    await _until(tester,
        () => find.byTooltip('打开文件树').hitTestable().evaluate().isNotEmpty ||
            find.byTooltip('收起文件树').hitTestable().evaluate().isNotEmpty,
        'locate SQL file-tree control');
    final closed = find.byTooltip('打开文件树').hitTestable();
    if (closed.evaluate().isNotEmpty) await tester.tap(closed);
    await tester.pump(const Duration(milliseconds: 300));
    await _until(tester,
        () => find.byTooltip('收起文件树').hitTestable().evaluate().isNotEmpty &&
            root(first).hitTestable().evaluate().isNotEmpty,
        'show SQL workspace roots');
  }
  Future<void> drain(WidgetTester tester) async {
    var done = false;
    final pending = Future.wait<Object?>([
      WorkspaceStore.instance.settle(),
      for (final owner in projects) ProjectHistory.load(owner.path),
      store.refresh(),
    ]);
    unawaited(pending.then((_) => done = true));
    await _until(tester, () => done, 'drain real workspace/project write queues');
    await pending;
  }
  Future<void> unmountAndDrain(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester);
  }
  void expectHistoryBytes(Map<String, List<int>> expected) {
    for (final owner in projects) {
      expect(history(owner).readAsBytesSync(), orderedEquals(expected[owner.path]!),
          reason: 'Named SQL state must not rewrite ${owner.name} standalone history');
    }
  }
  void expectSourceBytes() {
    expect(source(first).readAsStringSync(), _firstSource);
    expect(source(second).readAsStringSync(), _secondSource);
  }
}

FileCursor _fileCursor(CodeLineSelection selection) => FileCursor(
  baseIndex: selection.baseIndex,
  baseOffset: selection.baseOffset,
  extentIndex: selection.extentIndex,
  extentOffset: selection.extentOffset,
);

void _expectCursor(CodeLineSelection actual, CodeLineSelection expected) {
  expect(actual.baseIndex, expected.baseIndex);
  expect(actual.baseOffset, expected.baseOffset);
  expect(actual.extentIndex, expected.extentIndex);
  expect(actual.extentOffset, expected.extentOffset);
}

Future<void> _until(WidgetTester tester, bool Function() complete,
    String operation) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (complete()) return;
    await tester.runAsync(() =>
        Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(complete(), isTrue, reason: '$operation did not finish.');
}
