import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/sql_projects_page.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  late _TestProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = sqlProfile;
    store = _TestProjectStore();
    auth = AuthStore();
    settings = SettingsStore();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    store.dispose();
    auth.dispose();
    settings.dispose();
  });

  Widget app() => MaterialApp(
    home: SqlProjectsPage(
      store: store,
      auth: auth,
      settings: settings,
      embedded: true,
    ),
  );

  Project project(String name, {String? cloudId}) => Project.create(
    name: name,
    path: Directory.systemTemp.path,
    cloudId: cloudId,
    language: 'SQL',
    type: 'sql',
  );

  testWidgets('project notifications refresh the visible list and search', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('暂无项目，点击“新建项目”。'), findsOneWidget);

    store.replace([project('Orders'), project('Inventory')]);
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索项目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'orders');
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Inventory'), findsNothing);

    store.replace([project('Inventory')]);
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsNothing);
    expect(find.text('没有匹配的项目。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline projects hide persisted cloud entries', (tester) async {
    store.replace([
      project('Local SQL'),
      project('Old cloud SQL', cloudId: 'proj_old'),
    ]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Local SQL'), findsOneWidget);
    expect(find.text('Old cloud SQL'), findsNothing);
    // Filtering the UI must preserve the existing registry entries.
    expect(store.projects, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}

class _TestProjectStore extends ProjectStore {
  List<Project> _entries = [];

  @override
  bool get loaded => true;

  @override
  List<Project> get projects => List.of(_entries);

  void replace(List<Project> projects) {
    _entries = List.of(projects);
    notifyListeners();
  }
}
