import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'mysql_ffi.dart';

/// Owns one app-private Oracle server; the launcher handles application death.
class LocalMySqlRuntime {
  LocalMySqlRuntime({
    required this.bundleDirectory,
    required this.dataDirectory,
    required this.libraryPath,
    required this.launcherPath,
    this.serverPath,
    this.serverUser,
    this.readinessTimeout = const Duration(seconds: 45),
  });

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static final LocalMySqlRuntime shared = _discover();
  static final Set<String> _ownedDirectories = {};

  final Directory bundleDirectory;
  final Directory dataDirectory;
  final String libraryPath;
  final String launcherPath;
  final String? serverPath;
  // Only explicit host fixtures may ask mysqld to run as root.
  final String? serverUser;
  final Duration readinessTimeout;
  Future<void> _tail = Future<void>.value();
  Process? _server;
  Future<int>? _serverExit;
  int? _exitCode;
  Directory? _ipcDirectory;
  RandomAccessFile? _lock;
  String? _ownedDirectory;
  String? _socket;
  String? _password;
  String _diagnostics = '';

  Future<Map<String, Object?>> invoke(
    String method,
    Map<String, Object?> arguments,
  ) => _serialize(() async {
    if (method != 'query' && method != 'executeScript') {
      throw ArgumentError.value(method, 'method');
    }
    try {
      await _ensureReady();
      return await _call(method, arguments);
    } on Object catch (error) {
      return _failure(error.toString(), script: method == 'executeScript');
    }
  });

  Future<void> stop() => _serialize(_stop);

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> arguments,
  ) => MySqlFfi.invoke(libraryPath, {
    ...arguments,
    'method': method,
    'socket': _socket,
    'password': _password,
  });

  Future<void> _ensureReady() async {
    if (_server != null && _exitCode == null) return;
    await _stop();
    if (!supported) {
      throw UnsupportedError('Local Oracle MySQL requires a desktop host.');
    }
    final server =
        serverPath ??
        p.join(
          bundleDirectory.path,
          'bin',
          Platform.isWindows ? 'mysqld.exe' : 'mysqld',
        );
    for (final path in [server, launcherPath, libraryPath]) {
      if (!await File(path).exists()) {
        throw StateError('Missing bundled MySQL file: $path');
      }
    }
    await dataDirectory.create(recursive: true);
    await _makePrivate(dataDirectory.path);
    final resolved = await dataDirectory.resolveSymbolicLinks();
    final owned = Platform.isWindows ? resolved.toLowerCase() : resolved;
    if (!_ownedDirectories.add(owned)) {
      throw StateError('The local MySQL data directory is already in use.');
    }
    _ownedDirectory = owned;
    RandomAccessFile? lock;
    try {
      lock = await File(
        p.join(dataDirectory.path, 'runtime.lock'),
      ).open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      _lock = lock;
    } on Object {
      await lock?.close();
      _ownedDirectories.remove(owned);
      _ownedDirectory = null;
      throw StateError('The local MySQL data directory is already in use.');
    }
    try {
      final versionResult = await _run(server, ['--no-defaults', '--version']);
      final version = RegExp(
        r'\bVer\s+(8\.\d+\.\d+[^\s]*)',
      ).firstMatch(versionResult)?.group(1);
      if (version == null || versionResult.contains('MariaDB')) {
        throw StateError(
          'The bundled server must be Oracle MySQL 8.x: $versionResult',
        );
      }
      final data = Directory(p.join(dataDirectory.path, 'data'));
      final marker = File(p.join(dataDirectory.path, 'initialized.json'));
      if (await marker.exists()) {
        final raw = jsonDecode(await marker.readAsString());
        if (raw is! Map ||
            raw['version'] != version ||
            raw['password'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['password'] as String) ||
            !await data.exists()) {
          throw StateError(
            'MySQL initialization metadata or server version does not match. Automatic upgrade is disabled.',
          );
        }
        _password = raw['password'] as String;
      } else {
        if (await data.exists()) {
          throw StateError(
            'MySQL data exists without successful initialization metadata.',
          );
        }
        final staging = await dataDirectory.createTemp('initializing-');
        await _makePrivate(staging.path);
        try {
          await _run(server, [
            '--no-defaults',
            '--initialize-insecure',
            '--basedir=${bundleDirectory.path}',
            '--datadir=${staging.path}',
            '--performance-schema=OFF',
            '--innodb-buffer-pool-size=32M',
            '--innodb-redo-log-capacity=16M',
            if (serverUser != null) '--user=$serverUser',
          ], timeout: const Duration(minutes: 3));
          _password = _randomHex(32);
          final pending = File(
            p.join(dataDirectory.path, 'initialized.pending.json'),
          );
          await pending.writeAsString(
            jsonEncode({'version': version, 'password': _password}),
            flush: true,
          );
          await _makePrivate(pending.path, directory: false);
          await staging.rename(data.path);
          await pending.rename(marker.path);
        } finally {
          if (await staging.exists()) await staging.delete(recursive: true);
        }
      }
      // A per-datadir lock stays held for the server's lifetime. Unix sockets
      // use a short private temporary directory to fit sockaddr_un on macOS.
      if (Platform.isWindows) {
        _socket = 'qfli_mysql_${_randomHex(16)}';
      } else {
        _ipcDirectory = await Directory.systemTemp.createTemp('qfli-mysql-');
        await _makePrivate(_ipcDirectory!.path);
        _socket = p.join(_ipcDirectory!.path, 'mysql.sock');
      }
      final init = File(p.join(dataDirectory.path, 'root.sql'));
      await init.writeAsString(
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '$_password';\n",
        flush: true,
      );
      await _makePrivate(init.path, directory: false);
      final process = await _start(server, [
        '--no-defaults',
        '--basedir=${bundleDirectory.path}',
        '--datadir=${data.path}',
        '--plugin-dir=${p.join(bundleDirectory.path, 'lib', 'plugin')}',
        '--lc-messages-dir=${p.join(bundleDirectory.path, 'share')}',
        '--socket=$_socket',
        '--skip-networking',
        '--mysqlx=0',
        '--skip-log-bin',
        '--performance-schema=OFF',
        '--max-connections=20',
        '--table-open-cache=64',
        if (Platform.isWindows) '--named-pipe',
        if (serverUser != null) '--user=$serverUser',
        '--upgrade=NONE',
        '--local-infile=0',
        '--secure-file-priv=NULL',
        '--max-allowed-packet=8M',
        '--innodb-buffer-pool-size=32M',
        '--innodb-redo-log-capacity=16M',
        '--init-file=${init.path}',
        '--pid-file=${p.join(dataDirectory.path, 'mysqld.pid')}',
        '--log-error=${p.join(dataDirectory.path, 'mysqld.log')}',
      ]);
      _server = process;
      _exitCode = null;
      _serverExit = process.exitCode.then((code) {
        _exitCode = code;
        return code;
      });
      _drain(process);
      final deadline = DateTime.now().add(readinessTimeout);
      Object? readinessError;
      while (_exitCode == null && DateTime.now().isBefore(deadline)) {
        final ready = await _call('query', {
          'schema': '',
          'source': 'SELECT VERSION(), @@version_comment',
          'params': <String?>[],
        });
        readinessError = ready['error'];
        if (ready['available'] == true && ready['exitCode'] == 0) {
          final rows = ready['rows'] as List;
          if ((rows.first as List).first != version ||
              rows.toString().contains('MariaDB')) {
            throw StateError(
              'The private MySQL server version does not match its bundle.',
            );
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final log = File(p.join(dataDirectory.path, 'mysqld.log'));
      final details = await log.exists()
          ? await log.readAsString()
          : _diagnostics;
      throw StateError(
        'Oracle MySQL did not become ready (exit $_exitCode, $readinessError): ${details.length > 8192 ? details.substring(details.length - 8192) : details}',
      );
    } on Object {
      await _stop();
      rethrow;
    }
  }

  Future<Process> _start(
    String server,
    List<String> arguments,
  ) => Process.start(
    launcherPath,
    ['$pid', server, ...arguments],
    workingDirectory: bundleDirectory.path,
    environment: {
      if (Platform.isWindows)
        'PATH':
            '${p.join(bundleDirectory.path, 'bin')};${p.join(bundleDirectory.path, 'lib')};${Platform.environment['PATH'] ?? ''}',
      if (Platform.isLinux)
        'LD_LIBRARY_PATH':
            '${p.join(bundleDirectory.path, 'lib')}:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
    },
  );

  Future<String> _run(
    String server,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final process = await _start(server, arguments);
    final output = StringBuffer();
    void collect(String value) {
      if (output.length < 8192) output.write(value);
    }

    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(collect);
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(collect);
    int status;
    try {
      status = await process.exitCode.timeout(timeout);
    } on Object {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      rethrow;
    } finally {
      await Future.wait([stdoutDone, stderrDone]);
    }
    if (status != 0) {
      throw StateError('MySQL command failed ($status): $output');
    }
    return output.toString();
  }

  void _drain(Process process) {
    _diagnostics = '';
    void collect(String value) {
      _diagnostics += value;
      if (_diagnostics.length > 8192) {
        _diagnostics = _diagnostics.substring(_diagnostics.length - 8192);
      }
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(collect);
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(collect);
  }

  Future<void> _stop() async {
    final process = _server;
    try {
      if (process != null) {
        if (_exitCode == null) {
          try {
            await _call('shutdown', {});
          } on Object {
            process.kill();
          }
        }
        try {
          await _serverExit!.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await _serverExit;
        }
      }
    } finally {
      _server = null;
      _serverExit = null;
      _exitCode = null;
      _socket = null;
      _password = null;
      final ipc = _ipcDirectory;
      _ipcDirectory = null;
      final lock = _lock;
      _lock = null;
      final owned = _ownedDirectory;
      _ownedDirectory = null;
      try {
        if (ipc != null && await ipc.exists()) {
          await ipc.delete(recursive: true);
        }
      } finally {
        try {
          if (lock != null) {
            try {
              await lock.unlock();
            } finally {
              await lock.close();
            }
          }
        } finally {
          if (owned != null) _ownedDirectories.remove(owned);
        }
      }
    }
  }

  static Future<void> _makePrivate(String path, {bool directory = true}) async {
    if (Platform.isWindows) return;
    final result = await Process.run('/bin/chmod', [
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('Cannot make MySQL storage private.', path);
    }
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Map<String, Object?> _failure(String error, {required bool script}) =>
      {
        'available': false,
        'exitCode': 127,
        'error': error,
        'sqlState': '',
        'columns': <String>[],
        'columnInfo': <Object>[],
        'rows': <Object>[],
        'affectedRows': 0,
        'truncated': false,
        if (script) 'results': <Object>[],
      };

  static LocalMySqlRuntime _discover() {
    final app = p.dirname(Platform.resolvedExecutable);
    final configured = Platform.environment['QFLI_MYSQL_BUNDLE'];
    final bundle = Directory(
      configured ??
          (Platform.isMacOS
              ? p.normalize(p.join(app, '..', 'Resources', 'qfli_mysql'))
              : p.join(app, 'qfli_mysql')),
    );
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null) {
      throw StateError('Cannot locate application-private MySQL storage.');
    }
    final String root;
    if (Platform.isWindows) {
      root =
          Platform.environment['LOCALAPPDATA'] ??
          p.join(home, 'AppData', 'Local');
    } else if (Platform.isMacOS) {
      root = p.join(home, 'Library', 'Application Support');
    } else {
      root =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(home, '.local', 'share');
    }
    return LocalMySqlRuntime(
      bundleDirectory: bundle,
      dataDirectory: Directory(p.join(root, 'qfli_sql', 'mysql')),
      launcherPath: p.join(
        bundle.path,
        'bin',
        Platform.isWindows ? 'qfli_mysql_launcher.exe' : 'qfli_mysql_launcher',
      ),
      libraryPath: p.join(
        bundle.path,
        Platform.isWindows ? 'bin' : 'lib',
        Platform.isWindows
            ? 'qfli_mysql_bridge.dll'
            : 'libqfli_mysql_bridge.${Platform.isMacOS ? 'dylib' : 'so'}',
      ),
    );
  }
}
