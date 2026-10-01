import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

final class _ScriptResult extends Struct {
  @Int32()
  external int available;
  @Int32()
  external int exitCode;
  @Int32()
  external int truncated;
  external Pointer<Utf8> output;
  external Pointer<Utf8> error;
}

/// Invokes the retained SQLite C engine on a worker isolate.
class SqliteFfi {
  static bool get supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  static Future<Map<String, Object?>> invoke(
    String method,
    Map<String, Object?> arguments, {
    String? libraryPath,
  }) => Isolate.run(() {
    final bindings = _Bindings(_openLibrary(libraryPath));
    final source = arguments['source'] as String;
    final databasePath = arguments['databasePath'] as String;
    if (source.contains('\x00') || databasePath.contains('\x00')) {
      throw const FormatException(
        'SQL source and database path cannot contain NUL.',
      );
    }
    return using((arena) {
      final sql = source.toNativeUtf8(allocator: arena);
      final path = databasePath.toNativeUtf8(allocator: arena);
      if (method == 'execute') {
        final result = arena<_ScriptResult>();
        try {
          if (bindings.execute(sql, path, 1024 * 1024, result) == 0) {
            throw StateError('SQLite script invocation failed.');
          }
          return <String, Object?>{
            'available': result.ref.available != 0,
            'exitCode': result.ref.exitCode,
            'output': _text(result.ref.output),
            'error': _text(result.ref.error),
            'truncated': result.ref.truncated != 0,
          };
        } finally {
          bindings.freeResult(result);
        }
      }
      if (method == 'executeScript') return bindings.script(arena, path, sql);
      if (method != 'query') throw ArgumentError.value(method, 'method');
      return bindings.query(
        arena,
        path,
        sql,
        (arguments['params'] as List?)?.cast<String?>() ?? const [],
      );
    });
  });

  static String _text(Pointer<Utf8> value, {int? length}) =>
      value == nullptr ? '' : value.toDartString(length: length);
}

DynamicLibrary _openLibrary(String? explicitPath) {
  final configured =
      explicitPath ?? Platform.environment['QFLI_SQLITE_LIBRARY'];
  if (configured != null) return DynamicLibrary.open(configured);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  final name = Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so';
  if (Platform.isAndroid) return DynamicLibrary.open(name);
  final app = p.dirname(Platform.resolvedExecutable);
  for (final path in [
    p.join(app, name),
    p.join(app, 'lib', name),
    p.join(
      Directory.current.path,
      'native',
      'build',
      Platform.operatingSystem,
      name,
    ),
  ]) {
    if (File(path).existsSync()) return DynamicLibrary.open(path);
  }
  throw StateError('The bundled SQLite C library was not found.');
}

class _Bindings {
  _Bindings(DynamicLibrary library)
    : execute = library
          .lookupFunction<
            Int32 Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Size,
              Pointer<_ScriptResult>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              int,
              Pointer<_ScriptResult>,
            )
          >('qfli_sql_execute'),
      freeResult = library
          .lookupFunction<
            Void Function(Pointer<_ScriptResult>),
            void Function(Pointer<_ScriptResult>)
          >('qfli_sql_result_free'),
      open = library
          .lookupFunction<
            Int32 Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              Int32,
              Pointer<Utf8>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Utf8>,
            )
          >('sqlite3_open_v2'),
      close = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_close'),
      busyTimeout = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_busy_timeout'),
      prepare = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Int32,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              int,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            )
          >('sqlite3_prepare_v2'),
      step = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_step'),
      finalize = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_finalize'),
      parameterCount = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_bind_parameter_count'),
      bindNull = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_bind_null'),
      bindText = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Pointer<Utf8>,
              Int32,
              Pointer<Void>,
            ),
            int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
          >('sqlite3_bind_text'),
      columnCount = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_column_count'),
      columnName = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('sqlite3_column_name'),
      columnType = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_type'),
      columnText = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('sqlite3_column_text'),
      columnBytes = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_bytes'),
      changes = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_changes'),
      errorMessage = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('sqlite3_errmsg');

  final int Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<_ScriptResult>)
  execute;
  final void Function(Pointer<_ScriptResult>) freeResult;
  final int Function(Pointer<Utf8>, Pointer<Pointer<Void>>, int, Pointer<Utf8>)
  open;
  final int Function(Pointer<Void>) close,
      step,
      finalize,
      parameterCount,
      columnCount,
      changes;
  final int Function(Pointer<Void>, int) busyTimeout,
      bindNull,
      columnType,
      columnBytes;
  final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Utf8>>,
  )
  prepare;
  final int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
  bindText;
  final Pointer<Utf8> Function(Pointer<Void>, int) columnName, columnText;
  final Pointer<Utf8> Function(Pointer<Void>) errorMessage;

  Map<String, Object?> query(
    Arena arena,
    Pointer<Utf8> path,
    Pointer<Utf8> source,
    List<String?> parameters,
  ) {
    final database = arena<Pointer<Void>>();
    try {
      final failure = _open(path, database);
      if (failure != null) return failure;
      return _statement(
        arena,
        database.value,
        source,
        parameters,
        _Budget(),
      ).result;
    } finally {
      if (database.value != nullptr) close(database.value);
    }
  }

  Map<String, Object?> script(
    Arena arena,
    Pointer<Utf8> path,
    Pointer<Utf8> source,
  ) {
    final database = arena<Pointer<Void>>();
    final results = <Map<String, Object?>>[];
    var summary = _emptyResult();
    try {
      final failure = _open(path, database);
      if (failure != null) return {...failure, 'results': results};
      var remaining = source;
      final budget = _Budget();
      while (SqliteFfi._text(remaining).trim().isNotEmpty) {
        if (results.length >= 512) {
          summary = {
            ...summary,
            'exitCode': 1,
            'error': 'SQL script exceeds the 512 statement limit.',
          };
          break;
        }
        final item = _statement(
          arena,
          database.value,
          remaining,
          const [],
          budget,
          allowTrailing: true,
        );
        summary = item.result;
        if (item.hasStatement) results.add(summary);
        if (summary['truncated'] == true) {
          summary = {
            ...summary,
            'exitCode': 1,
            'error': 'SQL script output exceeds the display limits.',
          };
        }
        if (summary['exitCode'] != 0 ||
            summary['truncated'] == true ||
            item.tail == nullptr ||
            item.tail.address <= remaining.address) {
          break;
        }
        remaining = item.tail;
      }
      return {...summary, 'results': results};
    } finally {
      if (database.value != nullptr) close(database.value);
    }
  }

  Map<String, Object?>? _open(
    Pointer<Utf8> path,
    Pointer<Pointer<Void>> database,
  ) {
    if (open(path, database, 6, nullptr) != 0) {
      return {
        ..._emptyResult(),
        'exitCode': 1,
        'error': database.value == nullptr
            ? 'SQLite database open failed.'
            : SqliteFfi._text(errorMessage(database.value)),
      };
    }
    busyTimeout(database.value, 3000);
    return null;
  }

  ({Map<String, Object?> result, Pointer<Utf8> tail, bool hasStatement})
  _statement(
    Arena arena,
    Pointer<Void> database,
    Pointer<Utf8> source,
    List<String?> parameters,
    _Budget budget, {
    bool allowTrailing = false,
  }) {
    final statement = arena<Pointer<Void>>();
    final tail = arena<Pointer<Utf8>>();
    final columns = <String>[];
    final rows = <List<String?>>[];
    var affectedRows = 0;
    var truncated = false;
    var error = '';
    var hasStatement = false;
    try {
      do {
        if (prepare(database, source, -1, statement, tail) != 0) {
          error = SqliteFfi._text(errorMessage(database));
          break;
        }
        hasStatement = statement.value != nullptr;
        if (!allowTrailing && SqliteFfi._text(tail.value).trim().isNotEmpty) {
          error = 'Only one SQL statement is allowed in a grid query.';
          break;
        }
        if (statement.value == nullptr) {
          if (parameters.isNotEmpty) {
            error = 'SQL parameter count does not match the supplied values.';
          }
          break;
        }
        if (parameters.length != parameterCount(statement.value)) {
          error = 'SQL parameter count does not match the supplied values.';
          break;
        }
        for (var index = 0; index < parameters.length; index++) {
          final value = parameters[index];
          final code = value == null
              ? bindNull(statement.value, index + 1)
              : bindText(
                  statement.value,
                  index + 1,
                  value.toNativeUtf8(allocator: arena),
                  utf8.encode(value).length,
                  Pointer<Void>.fromAddress(-1),
                );
          if (code != 0) {
            error = SqliteFfi._text(errorMessage(database));
            break;
          }
        }
        if (error.isNotEmpty) break;
        final count = columnCount(statement.value);
        for (var index = 0; index < count; index++) {
          columns.add(SqliteFfi._text(columnName(statement.value, index)));
        }
        while (true) {
          final code = step(statement.value);
          if (code == 101) {
            affectedRows = count == 0 ? changes(database) : 0;
            break;
          }
          if (code != 100) {
            error = SqliteFfi._text(errorMessage(database));
            break;
          }
          if (budget.rows >= 500) {
            truncated = true;
            break;
          }
          final row = <String?>[];
          for (var index = 0; index < count; index++) {
            if (columnType(statement.value, index) == 5) {
              row.add(null);
              continue;
            }
            final text = columnText(statement.value, index);
            final length = columnBytes(statement.value, index);
            if (text == nullptr || budget.bytes + length > 1024 * 1024) {
              truncated = true;
              break;
            }
            budget.bytes += length;
            row.add(SqliteFfi._text(text, length: length));
          }
          if (truncated) break;
          rows.add(row);
          budget.rows++;
        }
      } while (false);
    } finally {
      if (statement.value != nullptr) finalize(statement.value);
    }
    return (
      tail: tail.value,
      hasStatement: hasStatement,
      result: {
        'available': true,
        'exitCode': error.isEmpty ? 0 : 1,
        'error': error,
        'columns': columns,
        'rows': rows,
        'affectedRows': affectedRows,
        'truncated': truncated,
      },
    );
  }
}

Map<String, Object?> _emptyResult() => {
  'available': true,
  'exitCode': 0,
  'error': '',
  'columns': <String>[],
  'rows': <List<String?>>[],
  'affectedRows': 0,
  'truncated': false,
};

class _Budget {
  int rows = 0;
  int bytes = 0;
}
