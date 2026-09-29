import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';

void main() {
  test('quotes SQL identifiers and rejects unsafe file names', () async {
    final root = await Directory.systemTemp.createTemp('qfli_workspace_test_');
    addTearDown(() => root.delete(recursive: true));
    final workspace = SqlWorkspaceRepository(root: root);

    expect(SqlWorkspaceRepository.quoteIdentifier('select'), '"select"');
    expect(SqlWorkspaceRepository.quoteIdentifier('姓名'), '"姓名"');
    expect(() => workspace.databasePath('../escape'), throwsArgumentError);
    expect(() => workspace.databasePath('with\u0000null'), throwsArgumentError);
  });
}
