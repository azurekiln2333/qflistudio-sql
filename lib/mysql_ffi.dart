import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Executes the Oracle C API on a worker and frees JSON in the allocating DLL.
class MySqlFfi {
  static Future<Map<String, Object?>> invoke(
    String libraryPath,
    Map<String, Object?> request,
  ) => Isolate.run(() {
    final library = _openLibrary(libraryPath);
    final invoke = library
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>, Size),
          Pointer<Utf8> Function(Pointer<Utf8>, int)
        >('qfli_mysql_invoke');
    final release = library
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('qfli_mysql_free');
    final encoded = jsonEncode(request);
    final input = encoded.toNativeUtf8();
    Pointer<Utf8> result = nullptr;
    try {
      result = invoke(input, utf8.encode(encoded).length);
      if (result == nullptr) {
        throw StateError('Oracle MySQL invocation failed.');
      }
      final raw = jsonDecode(result.toDartString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid Oracle MySQL result.');
      }
      return Map<String, Object?>.from(raw);
    } finally {
      if (result != nullptr) release(result);
      malloc.free(input);
    }
  });
}

DynamicLibrary _openLibrary(String path) {
  if (!Platform.isWindows) return DynamicLibrary.open(path);
  final kernel = DynamicLibrary.open('kernel32.dll');
  final load = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, int)
      >('LoadLibraryExW');
  final free = kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('FreeLibrary');
  final lastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  return using((arena) {
    // Resolve Oracle/OpenSSL dependencies beside the bridge, including paths
    // with spaces and non-ASCII characters, without changing process PATH.
    final handle = load(
      p.normalize(p.absolute(path)).toNativeUtf16(allocator: arena),
      nullptr,
      0x1100,
    );
    if (handle == nullptr) {
      throw StateError(
        'Cannot load bundled Oracle client (${lastError()}): $path',
      );
    }
    try {
      return DynamicLibrary.open(path);
    } finally {
      free(handle);
    }
  });
}
