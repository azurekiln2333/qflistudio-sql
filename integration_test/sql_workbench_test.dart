import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_requireAndroidTestSandbox);

  testWidgets('Android SQLite workbench edits rows and persists saved SQL', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'qfli_workbench_device_',
    );
    addTearDown(() => root.delete(recursive: true));
    final previousEngine = await SqlEnginePreference.load();
    addTearDown(() => SqlEnginePreference.save(previousEngine));
    await SqlEnginePreference.save(SqlEngineKind.sqlite);
    final repository = await SqlWorkspaceRepository.openDefault();
    final databaseName = 'device_work_${DateTime.now().microsecondsSinceEpoch}';
    await repository.createDatabase(databaseName);
    addTearDown(() => repository.deleteDatabase(databaseName));
    await repository.createTable(databaseName, 'people', const [
      SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
      SqlColumnDraft(name: 'name', type: 'TEXT'),
    ]);
    await repository.insertRow(databaseName, 'people', {'name': 'Before'});
    final libraryFile = File(p.join(root.path, 'sql_queries.json'));
    final library = await SqlQueryLibrary.open(libraryFile);
    final store = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(store.dispose);
    addTearDown(auth.dispose);
    addTearDown(settings.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    await tester.pumpWidget(
      MaterialApp(
        home: SqlWorkbenchPage(
          store: store,
          auth: auth,
          settings: settings,
          queryLibraryFactory: () async => library,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final databaseTile = find.widgetWithText(ListTile, databaseName).first;
    await tester.ensureVisible(databaseTile);
    await tester.tap(databaseTile);
    await tester.pumpAndSettle();
    final tableTile = find.widgetWithText(ListTile, 'people').first;
    await tester.ensureVisible(tableTile);
    await tester.tap(tableTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'After');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsOneWidget);
    expect((await repository.loadTable(databaseName, 'people')).rows, [
      ['1', 'After'],
    ]);

    await tester.tap(find.byTooltip('SQL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SELECT name FROM people');
    await tester.pump();
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(library.history.single.success, isTrue);
    expect(find.text('After'), findsOneWidget);

    await tester.ensureVisible(find.text('保存查询'));
    await tester.tap(find.text('保存查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'People');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final reopened = await SqlQueryLibrary.open(libraryFile);
    expect(reopened.saved.single.source, 'SELECT name FROM people');
    expect(reopened.history.single.database, databaseName);
    expect(tester.takeException(), isNull);
  });
}

const _testPackage = 'com.azurekiln.qfli.sqlab.integrationtest';

Future<void> _requireAndroidTestSandbox() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'This target requires the isolated Android test app.',
    );
  }
  final process = utf8.decode(
    (await File(
      '/proc/self/cmdline',
    ).readAsBytes()).takeWhile((byte) => byte != 0).toList(),
  );
  if (process != _testPackage) {
    throw StateError('Refusing the production Android application sandbox.');
  }
}
