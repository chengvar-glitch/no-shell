/// 真实主机冒烟：端口转发（-L / -R / -D）与跳板机。
///
/// 与 tool/smoke_ssh.dart 的分工：那个脚本用 `dart run` 跑纯 Dart 的传输层，
/// 这里必须走 App 自己的会话层（models / ChangeNotifier），只能在 Flutter 的
/// 测试 VM 里跑，因此落在 test/ 下。默认**跳过**——没有真实主机时它不该拦下
/// 任何人的 `flutter test`；要跑就给出目标主机：
///
/// ```
/// NOSHELL_SMOKE_HOST=192.0.2.10 NOSHELL_SMOKE_PASSWORD='...' \
///   flutter test test/forward_smoke_test.dart
/// ```
///
/// 可选：NOSHELL_SMOKE_USER（默认 root）、NOSHELL_SMOKE_PORT（默认 22）。
/// 凭据只经环境变量传入，不写入仓库。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/jump_host.dart';
import 'package:no_shell/ssh/port_forward_runtime.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';

final _env = Platform.environment;
final _host = _env['NOSHELL_SMOKE_HOST'];
final _password = _env['NOSHELL_SMOKE_PASSWORD'];
final _user = _env['NOSHELL_SMOKE_USER'] ?? 'root';
final _port = int.tryParse(_env['NOSHELL_SMOKE_PORT'] ?? '') ?? 22;

/// 没给主机就整组跳过：这是需要真机的冒烟，不是单元测试。
final _skip = _host == null || _password == null
    ? '未设置 NOSHELL_SMOKE_HOST / NOSHELL_SMOKE_PASSWORD，跳过真实主机冒烟'
    : null;

SshServer _server({
  required String id,
  required String name,
  required String host,
  required int port,
  String? jump,
}) => SshServer(
  id: id,
  group: 'smoke',
  name: name,
  host: host,
  port: port,
  username: _user,
  authMethod: AuthMethod.password,
  jumpServerId: jump,
);

final _target = _server(
  id: 'smoke-target',
  name: 'smoke-target',
  host: _host ?? 'localhost',
  port: _port,
);

SshCredentials get _credentials => SshCredentials(password: _password);

/// 建一条真实会话并把连接阶段跑完；失败时把原因带进断言信息里。
Future<TerminalSession> _connect({
  SshServer? server,
  List<SshHop> jumps = const [],
}) async {
  final session = TerminalSession(
    server: server ?? _target,
    credentials: _credentials,
    jumps: jumps,
    // hostKeys 省略（null）：冒烟不做 TOFU 校验，与 tool/smoke_ssh.dart 一致。
  );
  addTearDown(session.dispose);
  await session.start();
  expect(
    session.phase,
    TerminalPhase.connected,
    reason: '连接失败：${session.error}',
  );
  return session;
}

/// 借会话里的交互式 shell 跑一条命令，返回缓冲区全文。
///
/// 用 shell 而不是另开 exec 通道：这条路径与界面完全一致，顺带验证
/// 「转发 + 终端」同时挂在一条连接上互不干扰。
Future<String> _runShell(TerminalSession session, String command) async {
  final marker = 'NOSHELL-DONE-${DateTime.now().microsecondsSinceEpoch}';
  session.terminal.textInput('$command; echo $marker\n');
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final text = session.terminal.buffer.getText();
    if (text.contains(marker)) return text;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return session.terminal.buffer.getText();
}

/// 单订阅套接字读取器：SOCKS5 握手要分几次读，而 `Socket` 的 stream
/// 只能被 listen 一次，所以由它统一收字节、按需「读到够 N 个」。
final class _SocketReader {
  _SocketReader(Socket socket) {
    socket.listen(
      _buffer.addAll,
      onDone: () => _closed = true,
      onError: (Object error) {
        _error = error;
        _closed = true;
      },
    );
  }

  final List<int> _buffer = [];
  bool _closed = false;
  Object? _error;

  /// 等到收到 [count] 个字节后取走这 [count] 个（对端关闭 / 超时时
  /// 返回手头已有的）。取走的语义很关键：SOCKS5 的回复要分几段解析，
  /// 不消费的话下一段读到的还是从第一个字节开始的整段数据。
  Future<List<int>> read(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_buffer.length < count &&
        !_closed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final error = _error;
    if (error != null) throw error;
    final taken = _buffer.length <= count
        ? List.of(_buffer)
        : _buffer.sublist(0, count);
    _buffer.removeRange(0, taken.length);
    return taken;
  }
}

/// 找一个当前空闲的本机端口：先绑 0 拿到端口号再放掉。
/// 与真正 bind 之间有极小的竞争窗口，冒烟脚本可以接受。
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void _stopAll(TerminalSession session) => session.forwards.stopAll();

void main() {
  group('真实主机冒烟：端口转发与跳板机', () {
    test('本地转发：本机端口 → 服务器视角的目标端口', () async {
      final session = await _connect();
      final localPort = await _freePort();
      await session.forwards.start(
        PortForwardRule(
          id: 'smoke-local',
          mode: PortForwardMode.local,
          localHost: '127.0.0.1',
          localPort: localPort,
          // 目标地址以服务器为视角：去连它自己的 sshd。
          remoteHost: '127.0.0.1',
          remotePort: 22,
        ),
      );
      final status = session.forwards.statusOf('smoke-local');
      expect(status.phase, PortForwardPhase.running, reason: status.error);

      final socket = await Socket.connect('127.0.0.1', localPort);
      addTearDown(socket.destroy);
      final reader = _SocketReader(socket);
      final banner = utf8.decode(await reader.read(40), allowMalformed: true);
      // ignore: avoid_print
      print('LOCAL FORWARD OK: $banner');
      expect(banner, startsWith('SSH-2.0'));
      _stopAll(session);
    }, skip: _skip);

    test('远程转发：服务器端口 → 本机回环服务', () async {
      final session = await _connect();

      // 服务器上有没有 bash 决定能不能用 /dev/tcp 回连，没有就跳过这一段。
      final probe = await _runShell(session, 'command -v bash');
      if (!probe.contains('/bash')) {
        // ignore: avoid_print
        print('REMOTE FORWARD SKIPPED: 服务器没有 bash(/dev/tcp 不可用)');
        return;
      }

      const marker = 'NOSHELL-REMOTE-OK';
      final local = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(local.close);
      local.listen((socket) {
        socket.write(marker);
        socket.flush().then((_) => socket.close());
      });

      await session.forwards.start(
        PortForwardRule(
          id: 'smoke-remote',
          mode: PortForwardMode.remote,
          localHost: '127.0.0.1',
          localPort: local.port,
          remoteHost: '127.0.0.1',
          // 0 = 让服务端挑一个空闲端口，实际端口从状态里读。
          remotePort: 0,
        ),
      );
      final status = session.forwards.statusOf('smoke-remote');
      expect(status.phase, PortForwardPhase.running, reason: status.error);
      final remotePort = status.boundPort;
      expect(remotePort, isNotNull);
      // ignore: avoid_print
      print('REMOTE FORWARD listening on server 127.0.0.1:$remotePort');

      final output = await _runShell(
        session,
        "bash -c 'exec 3<>/dev/tcp/127.0.0.1/$remotePort; head -c ${marker.length} <&3'",
      );
      expect(output, contains(marker), reason: output);
      _stopAll(session);
    }, skip: _skip);

    test('动态转发：SOCKS5 握手后拿到目标的 banner', () async {
      final session = await _connect();
      final localPort = await _freePort();
      await session.forwards.start(
        PortForwardRule(
          id: 'smoke-dynamic',
          mode: PortForwardMode.dynamic,
          localHost: '127.0.0.1',
          localPort: localPort,
        ),
      );
      final status = session.forwards.statusOf('smoke-dynamic');
      expect(status.phase, PortForwardPhase.running, reason: status.error);

      final socket = await Socket.connect('127.0.0.1', localPort);
      addTearDown(socket.destroy);
      final reader = _SocketReader(socket);
      // SOCKS5：只提供 NO AUTH 一种方法。
      socket.add([5, 1, 0]);
      expect((await reader.read(2)).sublist(0, 2), [5, 0]);
      // CONNECT 到服务器视角的 127.0.0.1:22。
      socket.add([5, 1, 0, 1, 127, 0, 0, 1, 0, 22]);
      // 回复长度取决于 ATYP（IPv4 4 字节 / IPv6 16 字节 / 域名带长度前缀），
      // 按协议自己算，别写死——写死就会把回复末尾的填充字节当成 banner 开头。
      final head = await reader.read(4);
      expect(head.sublist(0, 2), [5, 0], reason: 'SOCKS5 握手被拒绝');
      final addressLength = switch (head[3]) {
        1 => 4,
        4 => 16,
        3 => (await reader.read(1)).single,
        final atyp => throw StateError('未知的 SOCKS5 地址类型: $atyp'),
      };
      // 丢掉 BND.ADDR + BND.PORT，剩下的就是目标吐出来的 banner。
      await reader.read(addressLength + 2);
      final banner = utf8.decode(await reader.read(40), allowMalformed: true);
      // ignore: avoid_print
      print('DYNAMIC FORWARD OK: $banner');
      expect(banner, startsWith('SSH-2.0'));
      _stopAll(session);
    }, skip: _skip);

    test('跳板机：经中间主机连到目标，并在跳板链路上跑转发', () async {
      final jump = _server(
        id: 'smoke-jump',
        name: 'smoke-jump',
        host: _host ?? 'localhost',
        port: _port,
      );
      // 目标 = 跳板机自己的回环 sshd：链路真实存在（TCP → 跳板机 → 再认证一次）。
      final target = _server(
        id: 'smoke-via-jump',
        name: 'smoke-via-jump',
        host: '127.0.0.1',
        port: 22,
        jump: jump.id,
      );
      final chain = resolveJumpChain(
        target,
        (id) => id == jump.id ? jump : null,
      );
      expect(chain.map((s) => s.id), [jump.id]);

      final session = await _connect(
        server: target,
        jumps: [
          for (final hop in chain)
            SshHop(server: hop, credentials: _credentials),
        ],
      );
      final output = await _runShell(session, 'echo NOSHELL-JUMP-OK');
      expect(output, contains('NOSHELL-JUMP-OK'), reason: output);
      // ignore: avoid_print
      print('JUMP HOST OK: 经 ${jump.host} 连到 ${target.host}');

      // 转发也走这条跳板链路：验证 direct-tcpip 挂在了正确的那条连接上。
      final localPort = await _freePort();
      await session.forwards.start(
        PortForwardRule(
          id: 'smoke-jump-local',
          mode: PortForwardMode.local,
          localHost: '127.0.0.1',
          localPort: localPort,
          remoteHost: '127.0.0.1',
          remotePort: 22,
        ),
      );
      final status = session.forwards.statusOf('smoke-jump-local');
      expect(status.phase, PortForwardPhase.running, reason: status.error);
      final socket = await Socket.connect('127.0.0.1', localPort);
      addTearDown(socket.destroy);
      final banner = utf8.decode(
        await _SocketReader(socket).read(40),
        allowMalformed: true,
      );
      // ignore: avoid_print
      print('JUMP + LOCAL FORWARD OK: $banner');
      expect(banner, startsWith('SSH-2.0'));
      _stopAll(session);
    }, skip: _skip);
  });
}
