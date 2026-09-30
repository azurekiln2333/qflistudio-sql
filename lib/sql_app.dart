import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

import 'sql_workbench_page.dart';

class SqlLabApp extends StatelessWidget {
  const SqlLabApp({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
    required this.ready,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;
  final ValueListenable<bool> ready;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([settings, ready]),
    builder: (context, _) => MaterialApp(
      title: StudioProductCatalog.sqlab,
      debugShowCheckedModeBanner: false,
      locale: StudioLocalizations.resolveLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      ),
      supportedLocales: StudioLocalizations.supportedLocales,
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeModeValue,
      home: ready.value
          ? SqlWorkbenchPage(store: store, auth: auth, settings: settings)
          : const SplashScreen(),
    ),
  );
}
