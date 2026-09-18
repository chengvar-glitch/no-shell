import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/session_log.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:xterm/core.dart';

import 'support/transport_fakes.dart';

SshServer _server() => SshServer(
  id: 'srv-log',
  group: 'g',
  name: 'logged',
  host: '10.0.0.1',
  username: 'root',
);

/// 造一个跑过 [chunks] 的终端，返回它的日志快照。
SessionLog _logOf(List<String> chunks, {int maxLines = 100}) {
  final terminal = Terminal(maxLines: maxLines);
  for (final chunk in chunks) {
    terminal.write(chunk);
  }
  return SessionLog(terminal);
}

void main() {
  group('SessionLog 纯文本快照', () {
    test('OSC 标题与 bracketed paste 不进日志', () {
      // 真实遇到过的那一段：OSC 0 设窗口标题 + 开启 bracketed paste + 提示符。
      final log = _logOf([
        '\x1b]0;root@iZ7xv0ga5fud9vi9r8uqb4Z:~\x07\x1b[?2004h',
        '[root@iZ7xv0ga5fud9vi9r8uqb4Z ~]# ',
      ]);
      // 行内空白原样保留：提示符末尾那个空格也是画面的一部分。
      expect(log.text, '[root@iZ7xv0ga5fud9vi9r8uqb4Z ~]# ');
    });

    test('配色序列不进日志', () {
      final log = _logOf(['\x1b[0;32mOK\x1b[0m \x1b[1;31mFAIL\x1b[0m\n']);
      expect(log.text, 'OK FAIL');
    });

    test('\\r 重画只留最终一帧，不留中间态', () {
      final log = _logOf(['downloading\r 10%\r 55%\r100%\n']);
      expect(log.text, '100%loading');
    });

    test('转义序列被切成两块到达也解析正确', () {
      // 字节流按网络分片到达，序列从中间断开是常态；缓冲区解析器跨 write 有状态。
      final log = _logOf(['abc\x1b[?20', '04hdef\n']);
      expect(log.text, 'abcdef');
    });

    test('屏幕底部没写到的空行不算内容，中间的空行保留', () {
      final terminal = Terminal(maxLines: 100);
      expect(SessionLog(terminal).text, isEmpty);
      terminal.write('a\n\na\n');
      expect(SessionLog(terminal).text, 'a\n\na');
    });

    test('折行的长行仍是一行', () {
      final long = 'x' * 200;
      expect(_logOf(['$long\n']).text, long);
    });

    test('回滚内容留在日志里', () {
      final log = _logOf([
        for (var i = 0; i < 200; i++) 'line $i\n',
      ], maxLines: 1000);
      expect(log.text, startsWith('line 0\n'));
      expect(log.text, endsWith('line 199'));
    });

    test('超出终端行数上限后只剩最近的', () {
      final log = _logOf([
        for (var i = 0; i < 300; i++) 'line $i\n',
      ], maxLines: 50);
      expect(log.text, isNot(contains('line 0\n')));
      expect(log.text, endsWith('line 299'));
    });
  });

  group('TerminalSession 会话日志', () {
    test('远端输出进入会话日志，与终端缓冲同源', () async {
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: FakeTransport(lines: ['hello\n', 'world\n']),
      );
      addTearDown(session.dispose);
      await session.start();
      expect(session.sessionLog.text, 'hello\nworld');
    });

    test('远端控制序列不进入会话日志', () async {
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: FakeTransport(
          lines: ['\x1b]0;logged:~\x07\x1b[?2004h\x1b[32mready\x1b[0m\r\n'],
        ),
      );
      addTearDown(session.dispose);
      await session.start();
      expect(session.sessionLog.text, 'ready');
    });

    test('会话终止后日志保留，可供事后查看', () async {
      final transport = FakeTransport(lines: ['last words\n']);
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      addTearDown(session.dispose);
      await session.start();
      session.terminate();
      expect(session.phase, TerminalPhase.closed);
      expect(session.sessionLog.text, 'last words');
    });

    test('sendText 经终端 onOutput 发往远端，未连接时静默丢弃', () async {
      final transport = FakeTransport(lines: const [])..captureOutput = true;
      final session = TerminalSession(
        server: _server(),
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      addTearDown(session.dispose);
      // 未连接：onOutput 还没被传输层接上，发送是空操作。
      session.sendText('early\r');
      expect(transport.sent, isEmpty);
      await session.start();
      session.sendText('ls -la\r');
      expect(transport.sent, ['ls -la\r']);
    });
  });
}
