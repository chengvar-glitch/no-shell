/// 会话层测试共用的假传输层。
///
/// 之前五个测试文件各写一份（握手延迟 0 与 1ms 不统一、字段名也各异），
/// 收在这里之后驱动方式一致：要「连上后立即掉线」「握手失败」「把远端输出
/// 多行写进缓冲区」「抓发往远端的内容」都只改构造参数。
library;

import 'dart:async';

import 'package:no_shell/ssh/sftp.dart';
import 'package:xterm/core.dart';

import 'forward_fakes.dart';

/// 连接即成的假传输；不关心转发（一律按「会话未建立」拒绝）。
final class FakeTransport with NoForwardingTransport {
  FakeTransport({
    this.error,
    this.lines = const ['welcome'],
    this.handshakeDelay = Duration.zero,
    this.closeAfterConnect = false,
  });

  /// 非 null 时 [attach] 抛出该错误，模拟连接 / 认证失败。
  final Object? error;

  /// 连上以后写进终端的行；空列表表示「这个会话还没有输出」。
  final List<String> lines;

  /// 握手耗时：需要观察 connecting 阶段的测试给个非零值。
  final Duration handshakeDelay;

  /// 连接成功后立即触发远端关闭（模拟刚连上就掉线）。
  final bool closeAfterConnect;

  /// 置 true 时接管终端的 onOutput，把「发往远端」的内容收进 [sent]。
  bool captureOutput = false;

  /// 被发往远端的内容（[captureOutput] 为 true 时才有）。
  final List<String> sent = [];

  bool disposed = false;

  /// 挂上来的终端，用来断言「会话用的是自己那条终端的缓冲区」。
  Terminal? attachedTerminal;

  void Function()? _onClosed;

  /// 模拟远端断开（意外掉线）。
  void closeFromRemote() => _onClosed?.call();

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    // 与真实网络一致：握手要走事件循环，connecting 状态才可被观察。
    await Future<void>.delayed(handshakeDelay);
    final failure = error;
    if (failure != null) throw failure;
    _onClosed = onClosed;
    attachedTerminal = terminal;
    if (captureOutput) terminal.onOutput = sent.add;
    for (final line in lines) {
      terminal.write(line);
    }
    onConnected();
    if (closeAfterConnect) onClosed();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;
}
