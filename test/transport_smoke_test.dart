/// 真实主机冒烟：**App 自己的传输层**（`DartSsh2Transport`）。
///
/// 与 `tool/smoke_ssh.dart` 的分工：那个脚本用 `dart run` 跑纯 Dart 链路，
/// 验证的是协议本身与 dartssh2 适配器，绕开了界面连接时真正走的那一条路。
/// 这里跑的是 App 的传输实现：密码认证、PTY 交互、TOFU 指纹的记录 / 放行 /
/// 拒绝、SFTP 通道复用同一条连接，以及关闭之后的收尾。
///
/// 默认**跳过**——没有真实主机时它不该拦下任何人的 `flutter test`；要跑就给出
/// 目标主机：
///
/// ```
/// NOSHELL_SMOKE_HOST=192.0.2.10 NOSHELL_SMOKE_PASSWORD='...' \
///   flutter test test/transport_smoke_test.dart
/// ```
///
/// 可选：NOSHELL_SMOKE_USER（默认 root）、NOSHELL_SMOKE_PORT（默认 22）。
/// 凭据只经环境变量传入，不写入仓库。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/host_key_store.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _env = Platform.environment;

/// 空串表示没给主机（此时整组跳过）。
final _host = _env['NOSHELL_SMOKE_HOST'] ?? '';
final _password = _env['NOSHELL_SMOKE_PASSWORD'];
final _user = _env['NOSHELL_SMOKE_USER'] ?? 'root';
final _port = int.tryParse(_env['NOSHELL_SMOKE_PORT'] ?? '') ?? 22;

/// 没给主机就整组跳过：这是需要真机的冒烟，不是单元测试。
final _skip = _host.isEmpty || _password == null
    ? '未设置 NOSHELL_SMOKE_HOST / NOSHELL_SMOKE_PASSWORD，跳过真实主机冒烟'
    : null;

TerminalSession _session({HostKeyStore? hostKeys}) => TerminalSession(
  server: SshServer(
    id: 'smoke-transport',
    group: 'smoke',
    name: 'smoke-transport',
    host: _host,
    port: _port,
    username: _user,
    authMethod: AuthMethod.password,
  ),
  credentials: SshCredentials(password: _password),
  hostKeys: hostKeys,
);

/// 借会话里的交互式 shell 跑一条命令，返回缓冲区全文。
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

void main() {
  // 指纹存储走真实的 shared_preferences 实现（测试环境用内存后端）。
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DartSsh2Transport 真实链路', () {
    test('密码认证接通，PTY 里跑命令拿得到回显', () async {
      final session = _session();
      addTearDown(session.dispose);
      await session.start();
      expect(
        session.phase,
        TerminalPhase.connected,
        reason: '连接失败：${session.error}',
      );

      // 连接期间终端是接在传输上的（键入与 resize 都要有去处）。
      expect(session.terminal.onOutput, isNotNull);
      expect(session.terminal.onResize, isNotNull);

      final text = await _runShell(session, 'echo hello-from-noshell');
      expect(text, contains('hello-from-noshell'), reason: 'PTY 回显没回来');
    });

    test('首次连接记录指纹，第二次连接正常放行', () async {
      final store = SharedPreferencesHostKeyStore();
      expect(
        await store.load(_host, _port),
        isA<HostKeysNeverRecorded>(),
        reason: '前置：这台主机此前不该有记录',
      );

      final first = _session(hostKeys: store);
      addTearDown(first.dispose);
      await first.start();
      expect(
        first.phase,
        TerminalPhase.connected,
        reason: '首次连接失败：${first.error}',
      );

      final recorded = await store.load(_host, _port);
      expect(recorded, isA<HostKeysLoaded>(), reason: '首次连接必须把指纹记下来');
      final fingerprint =
          (recorded as HostKeysLoaded).records.single.fingerprint;
      expect(fingerprint, startsWith('SHA256:'));
      first.terminate();

      // 第二次：同一把密钥走「已记录」这条路，不该被判成「密钥变了」。
      final second = _session(hostKeys: store);
      addTearDown(second.dispose);
      await second.start();
      expect(
        second.phase,
        TerminalPhase.connected,
        reason: '第二次连接失败：${second.error}',
      );
    });

    test('指纹对不上时拒绝连接、带上实际指纹，且不改写可信记录', () async {
      final store = SharedPreferencesHostKeyStore();
      const planted = 'SHA256:planted-by-the-smoke-test';
      await store.save(_host, _port, const HostKeyRecord(fingerprint: planted));

      final session = _session(hostKeys: store);
      addTearDown(session.dispose);
      await session.start();

      expect(session.phase, TerminalPhase.failed, reason: '指纹不符必须拒绝连接');
      expect(
        session.errorKind,
        TerminalErrorKind.hostKey,
        reason: '应归类为 hostKey（疑似中间人）：${session.error}',
      );
      // 用户需要拿实际指纹去跟服务器核对，所以它必须一路带到界面。
      expect(session.hostKeyChanged?.fingerprint, startsWith('SHA256:'));
      expect(session.hostKeyChanged?.fingerprint, isNot(planted));

      // fail closed：不匹配时绝不能把记录改写成对方出示的那一把。
      final kept = await store.load(_host, _port) as HostKeysLoaded;
      expect(kept.records.map((record) => record.fingerprint), [planted]);
    });

    test('SFTP 通道复用同一条已认证连接', () async {
      final session = _session();
      addTearDown(session.dispose);
      await session.start();
      expect(session.phase, TerminalPhase.connected, reason: session.error);

      await session.sftp.ensureReady();
      expect(session.sftp.isReady, isTrue, reason: '${session.sftp.error}');
      expect(session.sftp.path, isNotNull);
      expect(session.sftp.entries, isA<List>());
    });

    test('会话关掉之后终端不再持有回调', () async {
      final session = _session();
      addTearDown(session.dispose);
      await session.start();
      expect(session.phase, TerminalPhase.connected, reason: session.error);
      final terminal = session.terminal;
      expect(terminal.onOutput, isNotNull);

      session.terminate();

      // 断线后会话仍可能留在注册表里等退避重连，终端视图也还挂着：此时键入
      // 或拖窗口若仍打到已关闭的传输上，写入会堆进无人消费的 sink，resize
      // 直接抛 SSHStateError('Transport is closed')。
      expect(terminal.onOutput, isNull, reason: '关掉后不该再往传输里写');
      expect(terminal.onResize, isNull, reason: '关掉后不该再触发 resize');
    });
  }, skip: _skip);
}
