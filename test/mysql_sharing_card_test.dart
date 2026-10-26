import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/mysql_sharing_card.dart';
import 'package:qfli_sql/mysql_sharing_controller.dart';

Map<String, Object?> reply({bool running = false}) => {
  'supported': true,
  'running': running,
  'host': '127.0.0.1',
  'port': 3306,
  'database': 'qfli_shared',
  'username': 'qfli_app',
  'password': running ? 'widget-native-secret' : '',
  'error': '',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_sql/test_mysql_sharing_card');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MySqlSharingController controller;
  late List<String> methods;

  setUp(() {
    methods = [];
    controller = MySqlSharingController(
      channel: channel,
      supportedPlatform: true,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return reply(running: call.method != 'stopSharing');
    });
  });

  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host({double textScale = 1}) => MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: MySqlSharingCard(controller: controller),
        ),
      ),
    ),
  );

  testWidgets('masks password and copies only after an explicit tap', (
    tester,
  ) async {
    final clipboard = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(methods, ['sharingStatus']);
    expect(find.text('服务已启动'), findsOneWidget);
    expect(find.textContaining('widget-native-secret'), findsNothing);
    expect(clipboard, isEmpty);
    await tester.tap(find.text('显示密码'));
    await tester.pump();
    expect(find.text('密码：widget-native-secret'), findsOneWidget);
    expect(clipboard, isEmpty);
    await tester.tap(find.text('隐藏密码'));
    await tester.pump();
    expect(find.textContaining('widget-native-secret'), findsNothing);
    await tester.tap(find.text('复制连接信息'));
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('Host: 127.0.0.1'));
    expect(clipboard.single, contains('Port: 3306'));
    expect(clipboard.single, contains('Database: qfli_shared'));
    expect(clipboard.single, contains('Username: qfli_app'));
    expect(clipboard.single, contains('Password: widget-native-secret'));
    expect(find.text('已复制连接信息'), findsOneWidget);
  });

  testWidgets('stop removes credentials and start uses the native reply', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('停止服务'));
    await tester.pumpAndSettle();
    expect(find.text('服务未启动'), findsOneWidget);
    expect(find.text('显示密码'), findsNothing);
    expect(find.text('复制连接信息'), findsNothing);
    await tester.tap(find.text('启动服务'));
    await tester.pumpAndSettle();
    expect(methods, ['sharingStatus', 'stopSharing', 'startSharing']);
    expect(find.text('服务已启动'), findsOneWidget);
    expect(find.textContaining('widget-native-secret'), findsNothing);
  });

  testWidgets('pending status disables actions without inventing credentials', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('复制连接信息'), findsNothing);
    pending.complete(reply());
    await tester.pumpAndSettle();
    expect(find.text('服务未启动'), findsOneWidget);
  });

  testWidgets('injected unsupported controller never calls native', (
    tester,
  ) async {
    controller.dispose();
    controller = MySqlSharingController(
      channel: channel,
      supportedPlatform: false,
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('当前设备不支持 MySQL 共享服务。'), findsOneWidget);
    expect(methods, isEmpty);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('narrow layout supports double text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(textScale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('刷新状态'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain stop retains retry without exposing native errors', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async => {
      ...reply(),
      'error': 'termination uncertain: widget-native-secret',
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('服务状态待确认'), findsOneWidget);
    expect(find.text('服务未启动'), findsNothing);
    expect(find.textContaining('widget-native-secret'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('known port failure names the target without claiming it is live', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (_) async => {
      ...reply(),
      'error': 'Loopback port 127.0.0.1:3306 is occupied or unavailable.',
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('端口 3306 已占用或不可用。'), findsOneWidget);
    expect(find.text('目标地址：127.0.0.1:3306'), findsOneWidget);
    expect(find.text('目标数据库：qfli_shared'), findsOneWidget);
    expect(find.text('目标用户名：qfli_app'), findsOneWidget);
    expect(find.text('服务已启动'), findsNothing);
    expect(find.text('复制连接信息'), findsNothing);
  });

  if (Platform.operatingSystem != 'ohos') {
    testWidgets('default unsupported host hides card without native calls', (
      tester,
    ) async {
      const nativeChannel = MethodChannel('qfli_sql/mysql');
      final nativeMethods = <String>[];
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        nativeMethods.add(call.method);
        return reply();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MySqlSharingCard())),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mysql-sharing-card')), findsNothing);
      expect(find.text('MySQL 共享服务'), findsNothing);
      expect(nativeMethods, isEmpty);
    });
  }

  testWidgets('pending reply after unmount never updates disposed widget', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(reply(running: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount preserves the injected controller ownership', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.refresh();
    expect(methods, ['sharingStatus', 'sharingStatus']);
    expect(controller.status!.running, isTrue);
  });
}
