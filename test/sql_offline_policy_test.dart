import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/cloud_mysql_database.dart';
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/mysql_workspace_repository.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = sqlProfile;
  });

  tearDown(() => StudioProfile.current = previousProfile);

  test(
    'stale cloud preference stays local and cannot be saved offline',
    () async {
      final storage = Directory.systemTemp.createTempSync('sql_offline_');
      addTearDown(() => storage.deleteSync(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => storage.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final file = File(p.join(storage.path, 'sql_engine.json'));
      file.writeAsStringSync('{"engine":"cloud"}');

      final reads = await Future.wait([
        SqlEnginePreference.load(),
        SqlEnginePreference.load(),
      ]);
      expect(reads, everyElement(SqlEngineKind.sqlite));
      expect(SqlEnginePreference.current, SqlEngineKind.sqlite);
      // An offline load preserves the user's prior preference on disk.
      expect(jsonDecode(file.readAsStringSync())['engine'], 'cloud');
      await expectLater(
        SqlEnginePreference.save(SqlEngineKind.cloud),
        throwsUnsupportedError,
      );
      expect(jsonDecode(file.readAsStringSync())['engine'], 'cloud');

      await SqlEnginePreference.save(SqlEngineKind.localMysql);
      expect(await SqlEnginePreference.load(), SqlEngineKind.localMysql);
      expect(jsonDecode(file.readAsStringSync())['engine'], 'localMysql');
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      expect(SqlEnginePreference.current, SqlEngineKind.sqlite);
    },
  );

  test(
    'cloud query and script stop before reading credentials or API',
    () async {
      final api = _UnexpectedApi();
      var tokenReads = 0;
      final database = CloudMySqlDatabase(
        token: () {
          tokenReads++;
          return 'stale-session';
        },
        client: api,
      );

      final query = await database.query(databasePath: '', source: 'SELECT 1');
      final script = await database.executeScript(
        databasePath: '',
        source: 'SELECT 1; SELECT 2;',
      );
      expect(query.available, isFalse);
      expect(query.error, SqlEnginePreference.cloudUnavailableMessage);
      expect(script.available, isFalse);
      expect(script.results, isEmpty);
      expect(tokenReads, 0);
      expect(api.calls, 0);
    },
  );

  test('cloud workspace stops before its account-info API request', () async {
    final api = _UnexpectedApi();
    await expectLater(
      MySqlWorkspaceRepository.openCloud(
        token: () => throw StateError('credentials must remain unread'),
        client: api,
      ),
      throwsUnsupportedError,
    );
    expect(api.calls, 0);
  });
}

class _UnexpectedApi extends ApiClient {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> sqlInfo(String token) async {
    calls++;
    throw StateError('unexpected network account lookup');
  }

  @override
  Future<Map<String, dynamic>> sqlQuery(
    String token, {
    String? database,
    required String source,
    List<String?> params = const [],
  }) async {
    calls++;
    throw StateError('unexpected network query');
  }

  @override
  Future<Map<String, dynamic>> sqlScript(
    String token, {
    String? database,
    required String source,
  }) async {
    calls++;
    throw StateError('unexpected network script');
  }
}
