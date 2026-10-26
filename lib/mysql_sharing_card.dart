import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mysql_sharing_controller.dart';

class MySqlSharingCard extends StatefulWidget {
  const MySqlSharingCard({super.key, this.controller});

  final MySqlSharingController? controller;

  @override
  State<MySqlSharingCard> createState() => _MySqlSharingCardState();
}

class _MySqlSharingCardState extends State<MySqlSharingCard> {
  late MySqlSharingController _controller;
  bool _revealPassword = false;
  bool _copyFailed = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _controller = widget.controller ?? MySqlSharingController();
    _controller.addListener(_changed);
    unawaited(_controller.refresh());
  }

  @override
  void didUpdateWidget(MySqlSharingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _controller.removeListener(_changed);
    if (oldWidget.controller == null) _controller.dispose();
    _revealPassword = false;
    _attach();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_controller.busy || _controller.status?.running != true) {
        _revealPassword = false;
      }
      _copyFailed = false;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final status = _controller.status;
    if (_controller.busy || status?.running != true) return;
    try {
      await Clipboard.setData(ClipboardData(text: status!.connectionDetails));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制连接信息')),
      );
    } on Object {
      if (mounted) setState(() => _copyFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null && !_controller.supportedPlatform) {
      return const SizedBox.shrink();
    }
    final status = _controller.status;
    final busy = _controller.busy;
    final supported = status?.supported ?? _controller.supportedPlatform;
    final running = status?.running == true;
    final label = busy
        ? '正在更新服务状态'
        : !supported
        ? '当前设备不支持 MySQL 共享服务。'
        : _controller.error != null
        ? '服务状态待确认'
        : status == null
        ? '尚未确认服务状态'
        : running
        ? '服务已启动'
        : '服务未启动';
    return Card(
      key: const ValueKey('mysql-sharing-card'),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('MySQL 共享服务', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(label),
            if (busy) const LinearProgressIndicator(),
            const Text('供同机应用连接。'),
            const Text('双应用连接仍待设备验证。'),
            const Text('应用退出后，服务可能停止。'),
            const Text('目标地址：127.0.0.1:3306'),
            const Text('目标数据库：qfli_shared'),
            const Text('目标用户名：qfli_app'),
            if (running && !busy) ...[
              Text(
                _revealPassword ? '密码：${status!.password}' : '密码：••••••••',
                key: const ValueKey('mysql-sharing-password'),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _revealPassword = !_revealPassword,
                    ),
                    icon: Icon(
                      _revealPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    label: Text(_revealPassword ? '隐藏密码' : '显示密码'),
                  ),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('复制连接信息'),
                  ),
                ],
              ),
              const Text('复制内容包含密码。'),
            ],
            if (_controller.error != null) Text(_controller.error!),
            if (_copyFailed) const Text('无法复制连接信息。'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: supported && !busy && !running
                      ? _controller.start
                      : null,
                  child: const Text('启动服务'),
                ),
                OutlinedButton(
                  onPressed: supported &&
                          !busy &&
                          (running || _controller.error != null)
                      ? _controller.stop
                      : null,
                  child: const Text('停止服务'),
                ),
                TextButton(
                  onPressed: busy ? null : _controller.refresh,
                  child: const Text('刷新状态'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
