import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('workbench edits native rows and persists saved SQL', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'qfli_workbench_device_',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = SqlWorkspaceRepository(root: root);
    await repository.createDatabase('device_work');
    await repository.createTable('device_work', 'people', const [
      SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
      SqlColumnDraft(name: 'name', type: 'TEXT'),
    ]);
    await repository.insertRow('device_work', 'people', {'name': 'Before'});
    final libraryFile = File(p.join(root.path, 'sql_queries.json'));
    final library = await SqlQueryLibrary.open(libraryFile);
    final store = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(store.dispose);
    addTearDown(auth.dispose);
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SqlWorkbenchPage(
          store: store,
          auth: auth,
          settings: settings,
          repositoryFactory: () async => repository,
          queryLibraryFactory: () async => library,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'After');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsOneWidget);
    expect((await repository.loadTable('device_work', 'people')).rows, [
      ['1', 'After'],
    ]);

    await tester.tap(find.text('SQL'));
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
    expect(reopened.history.single.database, 'device_work');
    expect(tester.takeException(), isNull);
  });
}
