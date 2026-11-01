import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/splash_screen.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';

import 'sql_home_shell.dart';

class SqlLabApp extends StatefulWidget {
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
  State<SqlLabApp> createState() => _SqlLabAppState();
}

class _SqlLabAppState extends State<SqlLabApp> {
  final _editors = RetainedEditorController();

  @override
  void dispose() {
    _editors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.settings, widget.ready]),
    builder: (context, _) => MaterialApp(
      navigatorObservers: [_editors.navigatorObserver],
      builder: (context, child) =>
          RetainedEditorHost(controller: _editors, child: child!),
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
      themeMode: widget.settings.themeModeValue,
      home: widget.ready.value
          ? SqlHomeShell(
              store: widget.store,
              auth: widget.auth,
              settings: widget.settings,
            )
          : const SplashScreen(),
    ),
  );
}
