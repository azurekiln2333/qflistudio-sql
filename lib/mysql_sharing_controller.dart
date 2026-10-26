import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sql_native_channel.dart';

class MySqlSharingStatus {
  const MySqlSharingStatus({
    required this.supported,
    required this.running,
    this.password = '',
    this.hasError = false,
    this.errorMessage,
  });

  factory MySqlSharingStatus.fromNative(Object? raw) {
    if (raw is! Map || raw['supported'] is! bool || raw['running'] is! bool) {
      throw const FormatException('Invalid MySQL sharing status');
    }
    final supported = raw['supported'] as bool;
    final running = raw['running'] as bool;
    if ((!supported && running) ||
        (supported &&
            (raw['host'] != host ||
                raw['port'] is! int ||
                raw['port'] != port ||
                raw['database'] != database ||
                raw['username'] != username)) ||
        (raw['password'] != null && raw['password'] is! String) ||
        (raw['error'] != null && raw['error'] is! String)) {
      throw const FormatException('Invalid MySQL sharing status');
    }
    final password = raw['password'] as String? ?? '';
    if (running && password.isEmpty) {
      throw const FormatException('Missing MySQL sharing credentials');
    }
    return MySqlSharingStatus(
      supported: supported,
      running: running,
      password: running ? password : '',
      hasError: (raw['error'] as String? ?? '').isNotEmpty,
      errorMessage: raw['error'] == _portUnavailable
          ? '端口 3306 已占用或不可用。'
          : null,
    );
  }

  static const host = '127.0.0.1';
  static const port = 3306;
  static const database = 'qfli_shared';
  static const username = 'qfli_app';
  static const _portUnavailable =
      'Loopback port 127.0.0.1:3306 is occupied or unavailable.';

  final bool supported;
  final bool running;
  final String password;
  final bool hasError;
  final String? errorMessage;

  String get connectionDetails =>
      'Host: $host\nPort: $port\nDatabase: $database\n'
      'Username: $username\nPassword: $password';
}

class MySqlSharingController extends ChangeNotifier {
  MySqlSharingController({MethodChannel? channel, bool? supportedPlatform})
    : _channel = channel ?? mysqlNativeChannel,
      supportedPlatform =
          supportedPlatform ?? (Platform.operatingSystem == 'ohos');

  final MethodChannel _channel;
  final bool supportedPlatform;
  MySqlSharingStatus? _status;
  MySqlSharingStatus? get status => _status;
  bool _busy = false;
  bool get busy => _busy;
  String? _error;
  String? get error => _error;
  bool _disposed = false;
  int _generation = 0;
  String? _pendingMethod;
  Future<void> _tail = Future<void>.value();

  Future<void> refresh() => _request('sharingStatus');
  Future<void> start() => _request('startSharing');
  Future<void> stop() => _request('stopSharing');

  Future<void> _request(String method) {
    if (_disposed ||
        (_busy &&
            (method != 'stopSharing' || _pendingMethod == 'stopSharing'))) {
      return Future<void>.value();
    }
    if (!supportedPlatform) {
      _status = const MySqlSharingStatus(supported: false, running: false);
      notifyListeners();
      return Future<void>.value();
    }
    final generation = ++_generation;
    _pendingMethod = method;
    _busy = true;
    _error = null;
    notifyListeners();
    return _tail = _tail.then((_) async {
      if (_disposed) return;
      try {
        final raw = await _channel.invokeMethod<Object?>(method);
        final next = MySqlSharingStatus.fromNative(raw);
        if (_disposed || generation != _generation) return;
        _status = next;
        _error = next.hasError
            ? next.errorMessage ?? '服务操作失败。请刷新状态。'
            : null;
      } on MissingPluginException {
        if (_disposed || generation != _generation) return;
        _status = const MySqlSharingStatus(supported: false, running: false);
        _error = '当前设备不支持 MySQL 共享服务。';
      } on Object {
        if (_disposed || generation != _generation) return;
        _status = null;
        _error = '无法确认服务状态。请刷新状态。';
      } finally {
        if (!_disposed && generation == _generation) {
          _busy = false;
          _pendingMethod = null;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _status = null;
    super.dispose();
  }
}
