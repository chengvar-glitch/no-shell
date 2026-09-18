import 'dart:async';
import 'dart:io';

import 'forward.dart';
import 'tunnel_gateway.dart';

/// 原生平台（桌面 / 移动）：真开套接字。
TunnelGateway createTunnelGateway() => const IoTunnelGateway();

final class IoTunnelGateway implements TunnelGateway {
  const IoTunnelGateway();

  @override
  Future<TunnelListener> listen(String host, int port) async {
    try {
      return _IoListener(await ServerSocket.bind(host, port));
    } on SocketException catch (error) {
      // 端口被占 / 没有权限绑这个地址：都不是网络故障，而是「这条转发开不了」。
      throw ForwardException(ForwardErrorKind.refused, error.toString());
    }
  }

  @override
  Future<DuplexChannel> dial(String host, int port) async {
    try {
      return _IoSocket(await Socket.connect(host, port));
    } on SocketException catch (error) {
      // 本机目标连不上：对端看到的是「连上又立刻断」，原因记在这里。
      throw ForwardException(ForwardErrorKind.refused, error.toString());
    }
  }
}

final class _IoListener implements TunnelListener {
  _IoListener(this._server);

  final ServerSocket _server;

  @override
  String get host => _server.address.address;

  @override
  int get port => _server.port;

  @override
  Stream<DuplexChannel> get connections =>
      _server.map<DuplexChannel>(_IoSocket.new);

  @override
  Future<void> close() => _server.close();
}

/// [Socket] 的薄包装：write 走 `add`（内部有缓冲，不会因为对端慢就阻塞
/// 事件循环），destroy 走 `destroy`（立刻放掉文件描述符）。
final class _IoSocket implements DuplexChannel {
  _IoSocket(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
  }

  final Socket _socket;

  @override
  Stream<List<int>> get stream => _socket;

  @override
  void write(List<int> data) {
    try {
      _socket.add(data);
    } on Object {
      // 对端已经关了：丢弃这一段，连接结束由 stream 的 done 上报。
    }
  }

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();
}
