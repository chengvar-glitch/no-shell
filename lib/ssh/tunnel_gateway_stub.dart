import 'forward.dart';
import 'tunnel_gateway.dart';

/// web：浏览器没有原始 TCP，端口转发整体不可用。
/// 抛 [UnsupportedError]，上层归类为 [TerminalErrorKind.unsupported]
/// （与 SSH 连接本身在 web 上的处理一致）。
TunnelGateway createTunnelGateway() => const UnsupportedTunnelGateway();

final class UnsupportedTunnelGateway implements TunnelGateway {
  const UnsupportedTunnelGateway();

  static Never _unsupported() => throw UnsupportedError(
    'Port forwarding requires raw TCP sockets, which the browser does not provide',
  );

  @override
  Future<TunnelListener> listen(String host, int port) async => _unsupported();

  @override
  Future<DuplexChannel> dial(String host, int port) async => _unsupported();
}
