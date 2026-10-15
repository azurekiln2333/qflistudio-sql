import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

/// Where SQLab runs SQL. SQLite on the device is the default; cloud MySQL is a
/// per-user practice space on a server isolated from business data.
enum SqlEngineKind { sqlite, cloud, localMysql }

abstract final class SqlEnginePreference {
  static SqlEngineKind _current = SqlEngineKind.sqlite;
  static bool _loaded = false;
  static Future<SqlEngineKind>? _loading;

  /// Supplies the signed-in QFLI token; set by the app entry point.
  static String? Function() token = () => null;

  static const cloudUnavailableMessage = '当前应用仅支持本地数据库，云 MySQL 已停用。';

  static bool get cloudEnabled => StudioProfile.current?.offlineOnly != true;

  static SqlEngineKind _effective(SqlEngineKind kind) =>
      kind == SqlEngineKind.cloud && !cloudEnabled
      ? SqlEngineKind.sqlite
      : kind;

  static SqlEngineKind get current => _effective(_current);

  static Future<File?> _file() async {
    final storage = await AppPaths.storageDirectory();
    return storage == null ? null : File(p.join(storage, 'sql_engine.json'));
  }

  static Future<SqlEngineKind> load() {
    if (_loaded) return Future.value(current);
    return _loading ??= _read().whenComplete(() => _loading = null);
  }

  static Future<SqlEngineKind> _read() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['engine'] == 'cloud') {
          _current = SqlEngineKind.cloud;
        } else if (data is Map && data['engine'] == 'localMysql') {
          _current = SqlEngineKind.localMysql;
        }
      }
    } on FileSystemException {
      // Unreadable preferences fall back to local SQLite.
    } on FormatException {
      // Corrupt preferences fall back to local SQLite.
    }
    _loaded = true;
    return current;
  }

  static Future<void> save(SqlEngineKind kind) async {
    if (kind == SqlEngineKind.cloud && !cloudEnabled) {
      throw UnsupportedError(cloudUnavailableMessage);
    }
    final loading = _loading;
    if (loading != null) await loading;
    final file = await _file();
    if (file == null) {
      throw const FileSystemException('无法访问应用数据目录，数据库引擎设置未保存。');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'engine': kind.name}),
      flush: true,
    );
    await temporary.rename(file.path);
    _current = kind;
    _loaded = true;
  }
}
