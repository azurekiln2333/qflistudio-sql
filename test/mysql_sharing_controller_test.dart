import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/mysql_sharing_controller.dart';

Map<String, Object?> reply({bool running = false, String error = ''}) => {
  'supported': true,
  'running': running,
  'host': '127.0.0.1',
  'port': 3306,
  'database': 'qfli_shared',
  'username': 'qfli_app',
  'password': running ? 'native-private-secret' : '',
  'error': error,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_sql/test_mysql_sharing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MySqlSharingController controller;

  setUp(() {
    controller = MySqlSharingController(
      channel: channel,
      supportedPlatform: true,
    );
  });

  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('unsupported platform never invokes native code', () async {
    final unsupported = MySqlSharingController(
      channel: channel,
      supportedPlatform: false,
    );
    addTearDown(unsupported.dispose);
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Unsupported hosts must not invoke MySQL sharing');
    });
    await unsupported.refresh();
    await unsupported.start();
    expect(unsupported.status!.supported, isFalse);
    expect(unsupported.status!.password, isEmpty);
  });

  test('credentials appear only after a native running reply', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final start = controller.start();
    expect(controller.busy, isTrue);
    expect(controller.status, isNull);
    pending.complete(reply(running: true));
    await start;
    expect(controller.status!.running, isTrue);
    expect(controller.status!.password, 'native-private-secret');
    expect(controller.busy, isFalse);
  });

  test('status restores credentials from native without starting', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return reply(running: true);
    });
    await controller.refresh();
    expect(methods, ['sharingStatus']);
    expect(controller.status!.password, 'native-private-secret');
  });

  test('stop queues behind start and rejects its stale running reply', () async {
    final started = Completer<void>();
    final pending = Completer<Object?>();
    final methods = <String>[];
    final observedRunning = <bool>[];
    controller.addListener(() {
      observedRunning.add(controller.status?.running ?? false);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'startSharing') {
        started.complete();
        return pending.future;
      }
      return reply();
    });
    final start = controller.start();
    await started.future;
    final stop = controller.stop();
    pending.complete(reply(running: true));
    await Future.wait([start, stop]);
    expect(methods, ['startSharing', 'stopSharing']);
    expect(observedRunning, everyElement(isFalse));
    expect(controller.status!.running, isFalse);
    expect(controller.status!.password, isEmpty);
    expect(controller.busy, isFalse);
  });

  test('stopped reply discards a password returned by native', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {
      ...reply(),
      'password': 'must-not-retain',
    });
    await controller.stop();
    expect(controller.status!.password, isEmpty);
  });

  test('invalid endpoint and missing credentials fail closed', () async {
    for (final malformed in [
      {...reply(running: true), 'host': '0.0.0.0'},
      {...reply(running: true), 'port': 3307},
      {...reply(running: true), 'port': 3306.0},
      {...reply(running: true), 'username': 'root'},
      {...reply(running: true), 'password': ''},
      {...reply(running: true), 'running': 'true'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => malformed);
      await controller.refresh();
      expect(controller.status, isNull);
      expect(controller.error, isNotNull);
      expect(controller.busy, isFalse);
    }
  });

  test('native errors never expose exception text or passwords', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'start', message: 'native-private-secret');
    });
    await controller.start();
    expect(controller.status, isNull);
    expect(controller.error, isNot(contains('native-private-secret')));
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => reply(error: 'native-private-secret'),
    );
    await controller.refresh();
    expect(controller.status!.hasError, isTrue);
    expect(controller.error, isNot(contains('native-private-secret')));
  });

  test('missing plugin is unsupported rather than running', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await controller.refresh();
    expect(controller.status!.supported, isFalse);
    expect(controller.status!.running, isFalse);
  });

  test('known port failure maps only the exact safe native message', () async {
    const nativeMessage =
        'Loopback port 127.0.0.1:3306 is occupied or unavailable.';
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => reply(error: nativeMessage),
    );
    await controller.start();
    expect(controller.error, '端口 3306 已占用或不可用。');
    expect(controller.status!.running, isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => reply(error: '$nativeMessage native-private-secret'),
    );
    await controller.refresh();
    expect(controller.error, '服务操作失败。请刷新状态。');
    expect(controller.error, isNot(contains('native-private-secret')));
  });

  test('disposing with a pending reply does not notify or restore state', () async {
    final pending = Completer<Object?>();
    final invoked = Completer<void>();
    final subject = MySqlSharingController(
      channel: channel,
      supportedPlatform: true,
    );
    var notifications = 0;
    subject.addListener(() => notifications++);
    messenger.setMockMethodCallHandler(channel, (_) {
      invoked.complete();
      return pending.future;
    });
    final start = subject.start();
    await invoked.future;
    subject.dispose();
    final before = notifications;
    pending.complete(reply(running: true));
    await start;
    expect(notifications, before);
    expect(subject.status, isNull);
  });
}
