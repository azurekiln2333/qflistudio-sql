import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qfli_studio_core/services/picker_service.dart';

abstract final class SqlDocumentService {
  static const maxBytes = 1024 * 1024;
  static const _channel = MethodChannel('qflistudio/platform');

  static Future<String> read(PickedDocument document) async {
    final path = document.path;
    final uri = document.uri;
    final List<int> bytes;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.length() > maxBytes) {
        throw const FormatException('SQL 文件超过 1 MiB 上限');
      }
      bytes = await file.readAsBytes();
    } else if (uri != null && uri.isNotEmpty) {
      final raw = await _channel.invokeMethod<Object?>('readSqlUri', {
        'uri': uri,
      });
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List) {
        bytes = Uint8List.fromList(raw.cast<int>());
      } else {
        throw const FormatException('系统未返回 SQL 文件内容');
      }
    } else {
      throw const FileSystemException('系统未返回可读文件');
    }
    if (bytes.length > maxBytes) {
      throw const FormatException('SQL 文件超过 1 MiB 上限');
    }
    return utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
  }

  static Future<void> write(PickedDocument document, String source) async {
    final bytes = Uint8List.fromList(utf8.encode(source));
    if (bytes.length > maxBytes) {
      throw const FormatException('SQL 文件超过 1 MiB 上限');
    }
    final path = document.path;
    final uri = document.uri;
    if (path != null && path.isNotEmpty) {
      await File(path).writeAsBytes(bytes, flush: true);
    } else if (uri != null && uri.isNotEmpty) {
      await PickerService.writeUri(uri, bytes);
    } else {
      throw const FileSystemException('系统未返回可写位置');
    }
  }
}
