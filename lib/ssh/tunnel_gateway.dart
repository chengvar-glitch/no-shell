/// 端口转发的本机一侧：监听端口、连出端口。
///
/// 这一层是整套转发里唯一真的需要 `dart:io` 的部分（浏览器没有原始 TCP），
/// 因此按 local_write 的老办法做条件导出：web 由桩实现兜底，调用方拿到
/// [UnsupportedError]，上层统一归类为「本平台不支持」。
library;

import 'dart:async';

import 'forward.dart';

export 'tunnel_gateway_stub.dart' if (dart.library.io) 'tunnel_gateway_io.dart';

/// 本地监听端口：本地转发（-L）与远程转发的本地落点都用它。
abstract interface class TunnelListener {
  /// 实际绑定地址与端口（端口填 0 时由系统分配，[port] 是分配结果）。
  String get host;

  int get port;

  /// 逐个到达的入站连接。
  Stream<DuplexChannel> get connections;

  Future<void> close();
}

/// 本地套接字网关。测试注入假实现即可在没有真实网络的情况下驱动转发逻辑。
abstract interface class TunnelGateway {
  /// 绑定本地监听端口；地址被占用 / 无权限时抛 [ForwardException]。
  Future<TunnelListener> listen(String host, int port);

  /// 连出到某个地址：远程转发（-R）把服务端送来的连接落到这里。
  Future<DuplexChannel> dial(String host, int port);
}
