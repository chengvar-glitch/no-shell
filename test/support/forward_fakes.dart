import 'dart:async';

import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/ssh/tunnel_gateway.dart';
import 'package:xterm/core.dart';

/// 给「不关心转发」的假传输层补上三个转发方法：一律按「会话未建立」拒绝。
///
/// 传输层接口每加一个能力，所有假实现都要跟着补；用 mixin 收在一处，
/// 免得四个测试文件里各抄一遍、还抄得不一样。
mixin NoForwardingTransport implements SshTransport {
  @override
  Future<DuplexChannel> openDirectChannel(String host, int port) async =>
      throw const ForwardException(
        ForwardErrorKind.notConnected,
        'fake transport has no forwarding',
      );

  @override
  Future<RemoteForwardListener> openRemoteForward({
    required String host,
    required int port,
  }) async => throw const ForwardException(
    ForwardErrorKind.notConnected,
    'fake transport has no forwarding',
  );

  @override
  Future<DynamicForwardProxy> openDynamicProxy({
    required String host,
    required int port,
  }) async => throw const ForwardException(
    ForwardErrorKind.notConnected,
    'fake transport has no forwarding',
  );
}

/// 内存里的双向通道：测试自己喂入站字节，也能读到对面写出去的字节。
final class FakeDuplexChannel implements DuplexChannel {
  FakeDuplexChannel({this.label = ''});

  /// 调试用标记，断言失败时能看出是哪一条通道。
  final String label;

  final _incoming = StreamController<List<int>>();
  final _written = StreamController<List<int>>.broadcast();

  /// 从这条通道写出去的全部字节。
  final List<int> received = [];

  bool closed = false;
  bool destroyed = false;

  bool get isClosed => closed || destroyed;

  /// 模拟对端发来一段字节。
  void feed(List<int> data) {
    if (_incoming.isClosed) return;
    _incoming.add(data);
  }

  /// 模拟对端关闭。
  void finish() {
    if (!_incoming.isClosed) _incoming.close();
  }

  /// 本端写出去的内容（另一端读到的东西）。
  Stream<List<int>> get outgoing => _written.stream;

  @override
  Stream<List<int>> get stream => _incoming.stream;

  @override
  void write(List<int> data) {
    received.addAll(data);
    if (!_written.isClosed) _written.add(data);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  void destroy() {
    destroyed = true;
    closed = true;
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  String toString() => 'FakeDuplexChannel($label)';
}

/// 假监听：测试通过 [connect] 手动投递一条入站连接。
final class FakeTunnelListener
    implements TunnelListener, RemoteForwardListener {
  FakeTunnelListener({required this.host, required this.port});

  @override
  final String host;

  @override
  final int port;

  final _connections = StreamController<DuplexChannel>();
  final List<FakeDuplexChannel> accepted = [];

  bool closed = false;

  /// 投递一条入站连接；监听已关闭时返回投出去的那条（便于断言被丢弃）。
  FakeDuplexChannel connect({String label = ''}) {
    final channel = FakeDuplexChannel(label: label);
    accepted.add(channel);
    if (!_connections.isClosed) _connections.add(channel);
    return channel;
  }

  @override
  Stream<DuplexChannel> get connections => _connections.stream;

  @override
  Future<void> close() async {
    closed = true;
    if (!_connections.isClosed) await _connections.close();
  }
}

/// 假本地网关：不碰真实套接字，监听与拨号全部可控。
final class FakeTunnelGateway implements TunnelGateway {
  final Map<String, FakeTunnelListener> listeners = {};
  final List<({String host, int port})> dialed = [];
  final List<FakeDuplexChannel> dialedChannels = [];

  /// 非 null 时 [listen] 抛出该错误（模拟端口被占用等）。
  Object? listenError;

  /// 非 null 时 [dial] 抛出该错误（模拟本地目标连不上）。
  Object? dialError;

  /// 监听端口为 0 时系统分配的端口（固定值，断言好写）。
  int assignedPort = 41000;

  FakeTunnelListener? listenerFor(String host, int port) =>
      listeners['$host:$port'];

  @override
  Future<TunnelListener> listen(String host, int port) async {
    final error = listenError;
    if (error != null) throw error;
    final actual = port == 0 ? assignedPort++ : port;
    final listener = FakeTunnelListener(host: host, port: actual);
    listeners['$host:$port'] = listener;
    return listener;
  }

  @override
  Future<DuplexChannel> dial(String host, int port) async {
    dialed.add((host: host, port: port));
    final error = dialError;
    if (error != null) throw error;
    final channel = FakeDuplexChannel(label: 'dial $host:$port');
    dialedChannels.add(channel);
    return channel;
  }
}

/// 可编程假传输层：转发能力全部可控，用来驱动 PortForwardManager。
final class FakeForwardTransport with NoForwardingTransport {
  FakeForwardTransport({this.remoteError, this.dynamicError});

  /// [attach] 是否走「连上」这条路；false 时永远不回调。
  bool connectOnAttach = true;

  bool disposed = false;
  Terminal? attachedTerminal;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    attachedTerminal = terminal;
    if (connectOnAttach) onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;

  /// 本地转发时每一次直连请求（远程目标地址）。
  final List<({String host, int port})> directRequests = [];
  final List<FakeDuplexChannel> directChannels = [];

  /// 非 null 时 [openDirectChannel] 抛出该错误。
  Object? directError;

  /// 远程转发的监听请求与返回的假监听。
  final List<({String host, int port})> remoteRequests = [];
  Object? remoteError;
  FakeTunnelListener? remoteListener;
  int remoteAssignedPort = 42000;

  /// 动态转发的请求与返回的假代理。
  final List<({String host, int port})> dynamicRequests = [];
  Object? dynamicError;
  final List<FakeDynamicProxy> proxies = [];

  @override
  Future<DuplexChannel> openDirectChannel(String host, int port) async {
    directRequests.add((host: host, port: port));
    final error = directError;
    if (error != null) throw error;
    final channel = FakeDuplexChannel(label: 'direct $host:$port');
    directChannels.add(channel);
    return channel;
  }

  @override
  Future<RemoteForwardListener> openRemoteForward({
    required String host,
    required int port,
  }) async {
    remoteRequests.add((host: host, port: port));
    final error = remoteError;
    if (error != null) throw error;
    final listener = FakeTunnelListener(
      host: host,
      port: port == 0 ? remoteAssignedPort++ : port,
    );
    remoteListener = listener;
    return listener;
  }

  @override
  Future<DynamicForwardProxy> openDynamicProxy({
    required String host,
    required int port,
  }) async {
    dynamicRequests.add((host: host, port: port));
    final error = dynamicError;
    if (error != null) throw error;
    final proxy = FakeDynamicProxy(host: host, port: port);
    proxies.add(proxy);
    return proxy;
  }
}

/// 假 SOCKS5 代理句柄。
final class FakeDynamicProxy implements DynamicForwardProxy {
  FakeDynamicProxy({required this.host, required this.port});

  @override
  final String host;

  @override
  final int port;

  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}
