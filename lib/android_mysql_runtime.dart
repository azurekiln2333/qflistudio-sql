import 'dart:io';

import 'package:flutter/services.dart';

import 'local_mysql_runtime.dart';

/// Native code lives in the APK's extracted library directory, data in filesDir.
abstract final class AndroidMySqlRuntime {
  static const _channel = MethodChannel('qfli_sql/mysql_runtime');
  static Future<LocalMySqlRuntime>? _prepared;

  static Future<void> stop() async {
    final pending = _prepared;
    if (pending != null) await (await pending).stop();
  }

  static Future<LocalMySqlRuntime> prepare() => _prepared ??= _prepare().then(
    (runtime) => runtime,
    onError: (Object error, StackTrace stack) {
      _prepared = null;
      Error.throwWithStackTrace(error, stack);
    },
  );

  static Future<LocalMySqlRuntime> _prepare() async {
    final layout = await _channel.invokeMapMethod<String, String>('layout');
    String path(String name) {
      final value = layout?[name];
      if (value == null || value.isEmpty || !value.startsWith('/')) {
        throw FormatException('Invalid Android MySQL layout: $name');
      }
      return value;
    }

    return LocalMySqlRuntime(
      bundleDirectory: Directory(path('bundleDirectory')),
      dataDirectory: Directory(path('dataDirectory')),
      temporaryDirectory: Directory(path('temporaryDirectory')),
      libraryDirectory: path('libraryDirectory'),
      serverPath: path('serverPath'),
      launcherPath: path('launcherPath'),
      libraryPath: path('libraryPath'),
    );
  }
}
