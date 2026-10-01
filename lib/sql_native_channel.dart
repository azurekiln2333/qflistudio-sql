import 'package:flutter/services.dart';

import 'sqlite_ffi.dart';

const MethodChannel sqlNativeChannel = MethodChannel('qfli_sql/native');
const MethodChannel mysqlNativeChannel = MethodChannel('qfli_sql/mysql');

Future<Object?> invokeSqliteNative(
  String method,
  Map<String, Object?> arguments, {
  MethodChannel? channel,
}) async {
  if (channel != null || !SqliteFfi.supported) {
    return (channel ?? sqlNativeChannel).invokeMethod<Object?>(
      method,
      arguments,
    );
  }
  try {
    return await SqliteFfi.invoke(method, arguments);
  } on Object catch (error) {
    throw PlatformException(code: 'sqlite_native', message: error.toString());
  }
}
