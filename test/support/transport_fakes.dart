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

  /// 握手耗时；零值表示不耗真实时间，只让出一个微任务。
  /// 想让它停在 connecting 等下一帧，给非零值。
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
    // 握手要让出一次调度，否则 attach 会同步跑完：`open()` 返回时状态已经是
    // connected，想观察 connecting 的调用方永远看不见它。
    // 但零延迟不能退化成 `Future.delayed(Duration.zero)`——那是真 Timer，
    // widget 测试跑在 fake-async 区域里，假时钟不推进它就不会完成，而把
    // `await session.start()` 写在测试体里时没人推进：直接死锁。让出微任务
    // 即可，它由 fake-async 的 flushMicrotasks 正常兑现。
    if (handshakeDelay > Duration.zero) {
      await Future<void>.delayed(handshakeDelay);
    } else {
      await Future<void>.microtask(() {});
    }
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
