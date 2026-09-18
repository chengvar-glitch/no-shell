/// 端口转发的公共类型：一条通道、一个服务端监听、一个本地代理。
///
/// 这些接口刻意不暴露 dartssh2 的类型：传输层（[SshTransport]）与运行时
/// （PortForwardManager）都只依赖它们，测试里换成假实现就能在没有真实
/// SSH 的情况下驱动整套转发逻辑。
library;

import 'dart:async';

/// 一条双向字节通道：本地转发的每个连接、远程转发的每个入站连接都是它。
abstract interface class DuplexChannel {
  /// 对端发来的字节；流结束时表示对端关闭。
  Stream<List<int>> get stream;

  /// 写入对端；对端已关闭时不该抛异常，连接结束由 [stream] 的结束上报。
  void write(List<int> data);

  /// 关闭本端，可重复调用。
  Future<void> close();

  /// 立刻断开，不等对端确认。取消 / 失败路径用它，避免连接悬着。
  void destroy();
}

/// 服务端监听型转发（`ssh -R`）：请求由 SSH 服务器监听
/// [host]:[port]，把每个入站连接作为一条 [DuplexChannel] 交回本地。
abstract interface class RemoteForwardListener {
  /// 服务端实际监听的地址与端口（端口填 0 时由服务端分配）。
  String get host;

  int get port;

  Stream<DuplexChannel> get connections;

  /// 取消监听；已建立的连接不受影响，由调用方各自关闭。
  Future<void> close();
}

/// 本地 SOCKS5 代理（`ssh -D`）。
abstract interface class DynamicForwardProxy {
  String get host;

  int get port;

  Future<void> close();
}

/// 建立转发通道失败的原因归类，供界面挑选本地化文案。
enum ForwardErrorKind {
  /// 会话还没建立（或已经断开）。
  notConnected,

  /// 本平台没有原始 TCP（web），端口转发整体不可用。
  unsupported,

  /// 服务端 / 目标 / 本地端口拒绝：通道打开失败、端口占用、绑定不被允许。
  refused,

  /// 网络中断或超时。
  network,

  other,
}

/// 转发通道建不起来。原始错误串随 [detail] 暴露给界面做详情展示。
final class ForwardException implements Exception {
  const ForwardException(this.kind, this.detail);

  final ForwardErrorKind kind;
  final String detail;

  @override
  String toString() => detail;
}

/// 把平台各异的错误归类成 [ForwardErrorKind]。
///
/// 只认领通用类型：dartssh2 的具体错误在 dartssh2_transport 里归类，
/// 本地套接字错误在 tunnel_gateway_io 里归类——那两个文件才该知道自己的
/// 错误长什么样，这里保持与平台无关（web 也要能编译）。
ForwardException forwardErrorFrom(Object error) {
  if (error is ForwardException) return error;
  if (error is UnsupportedError) {
    return ForwardException(ForwardErrorKind.unsupported, error.toString());
  }
  if (error is TimeoutException) {
    return ForwardException(ForwardErrorKind.network, error.toString());
  }
  return ForwardException(ForwardErrorKind.other, error.toString());
}
