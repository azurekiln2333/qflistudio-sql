import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:qfli_studio_core/editor/editor_fonts.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import 'sql_runner.dart';
import 'sql_app.dart';
import 'sql_tools_tab.dart';
import 'sql_code_analyzer.dart';

/// 本 App 的产品名。窗口标题、任务切换器和应用内顶栏都读它。
const String _appTitle = StudioProductCatalog.sqlab;

/// SQL 版档位：保留共享项目编辑器，只服务 SQL。
///
/// 单独提出来是为了让测试能直接断言档位，而不必为了一个常量去跑 `main()`。
const StudioProfile sqlProfile = StudioProfile(
  id: 'sql',
  appTitle: _appTitle,
  templates: [ProjectTemplate.empty, ProjectTemplate.sql],
  isOffline: true,
  runner: SqlProgramRunner(),
  productKey: StudioProductCatalog.sqlabKey,
  showHomeTabs: false,
  runtimeKind: 'oracle-mysql-native',
  runtimeStatus: 'unavailable',
  supportedFileExtensions: ['.sql'],
  // Teaches the standalone and editor terminals the SQL/mysql/sqlite3
  // commands this product ships. Without it those commands are reported as
  // unsupported on mobile, where no system shell exists to fall back to.
  terminalCommandDelegate: SqlTerminalCommands.execute,
  toolsTabBuilder: buildSqlToolsTab,
  codeAnalyzer: SqlCodeAnalyzer(),
  // main.sql 排在默认入口表前面，保证本版一定先命中它。
  entryFileNames: ['main.sql', 'src/main.sql'],
);

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final nativeStartup = !kIsWeb && defaultTargetPlatform == TargetPlatform.ohos;
  if (nativeStartup) binding.deferFirstFrame();
  EditorFonts.registerLicense();

  // 在 runApp 之前定档。
  StudioProfile.current = sqlProfile;

  final store = ProjectStore();
  final auth = AuthStore();
  final settings = SettingsStore();
  final ready = ValueNotifier<bool>(false);
  runApp(SqlLabApp(store: store, auth: auth, settings: settings, ready: ready));

  const platformChannel = MethodChannel('qflistudio/platform');
  Future<void> reportProgress(double progress) async {
    try {
      await platformChannel.invokeMethod<void>('startupProgress', {
        'progress': progress,
      });
    } on PlatformException catch (error) {
      debugPrint('Startup progress unavailable: ${error.code}');
    } on MissingPluginException {
      // Other entry shells use the Flutter startup screen.
    }
  }

  Future<void> completeStartup() async {
    try {
      final minimumDisplay = nativeStartup
          ? Future<void>.delayed(const Duration(milliseconds: 1100))
          : Future<void>.value();
      if (nativeStartup) {
        // Let the native splash subscribe before reporting initialization work.
        await Future<void>.delayed(const Duration(milliseconds: 160));
        unawaited(reportProgress(0.05));
      }
      await AppBootstrap.run(
        store: store,
        auth: auth,
        settings: settings,
        ready: ready,
        onProgress: nativeStartup
            ? (progress) => unawaited(reportProgress(0.05 + progress * 0.95))
            : null,
      );
      await Future.wait([
        minimumDisplay,
        if (nativeStartup)
          Future<void>.delayed(const Duration(milliseconds: 320)),
      ]);
      // Submit a laid-out home page as the first frame beneath the native splash.
      if (nativeStartup) await binding.endOfFrame;
    } finally {
      if (nativeStartup) binding.allowFirstFrame();
    }
  }

  binding.addPostFrameCallback((_) {
    unawaited(completeStartup());
  });
}
