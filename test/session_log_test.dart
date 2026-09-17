import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/session_log.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:xterm/core.dart';

import 'support/forward_fakes.dart';

/// 输出先写进终端、再由远端关闭的假传输。
final class _EchoTransport with NoForwardingTransport {
  _EchoTransport(this.lines);

  final List<String> lines;

  /// 传输层把终端的 onOutput 接到这里，模拟「发给远端」。
  void Function(String)? onAttachOutput;

  bool disposed = false;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final sink = onAttachOutput;
    if (sink != null) terminal.onOutput = sink;
    for (final line in lines) {
      terminal.write(line);
    }
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake');

  @override
  void dispose() => disposed = true;
}

SshServer _server() => SshServer(
  id: 'srv-log',
  group: 'g',
  name: 'logged',
  host: '10.0.0.1',
  username: 'root',
);

void main() {
  group('SessionLog', () {
    test('顺序追加、text 还原原文', () {
      final log = SessionLog();
      log.append('hello ');
      log.append('world\n');
      expect(log.text, 'hello world\n');
      expect(log.isEmpty, isFalse);
    });

    test('空段落不改变内容', () {
      final log = SessionLog();
      log.append('');
      expect(log.isEmpty, isTrue);
    });

    test('超出容量时丢弃最旧的头部，保留最近的尾部', () {
      final log = SessionLog(capacity: 10);
      // 一次灌入远超两倍容量：裁剪到只剩最后 10 个字符。
      log.append('a' * 40);
      expect(log.text, 'a' * 10);
      // 之后的追加继续生效；未到两倍容量不会再次裁剪。
      log.append('b');
      expect(log.text, 'a' * 10 + 'b');
    });

    test('攒批裁剪：在容量与两倍容量之间不裁，保住最近的完整性', () {
      final log = SessionLog(capacity: 10);
      log.append('x' * 15);
      // 15 < 20（两倍容量）：暂不裁剪，整体都还在。
      expect(log.text, 'x' * 15);
      log.clear();
      expect(log.text, isEmpty);
      expect(log.isEmpty, isTrue);
    });
  });

  group('LoggingTerminal', () {
    test('write 同步落进转录', () {
      final terminal = LoggingTerminal(maxLines: 100);
      terminal.write('login: ');
      terminal.write('root\n');
      expect(terminal.log.text, 'login: root\n');
      expect(terminal.buffer.lines.length, greaterThanOrEqualTo(1));
    });
  });

  group('TerminalSession 会话日志', () {
    test('远端输出进入会话日志，与终端缓冲并存', () async {
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: _EchoTransport(['hello\n', 'world\n']),
      );
      addTearDown(session.dispose);
      await session.start();
      expect(session.sessionLog.text, 'hello\nworld\n');
    });

    test('会话终止后日志保留，可供事后查看', () async {
      final transport = _EchoTransport(['last words\n']);
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      addTearDown(session.dispose);
      await session.start();
      session.terminate();
      expect(session.phase, TerminalPhase.closed);
      expect(session.sessionLog.text, 'last words\n');
    });

    test('sendText 经终端 onOutput 发往远端，未连接时静默丢弃', () async {
      final sent = <String>[];
      final transport = _EchoTransport(const [])..onAttachOutput = sent.add;
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      addTearDown(session.dispose);
      // 未连接：onOutput 还没被传输层接上，发送是空操作。
      session.sendText('early\r');
      expect(sent, isEmpty);
      await session.start();
      session.sendText('ls -la\r');
      expect(sent, ['ls -la\r']);
    });
  });
}
