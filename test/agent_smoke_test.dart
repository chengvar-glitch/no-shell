/// 真实主机冒烟：Agent 认证（SSH_AUTH_SOCK 指向的本机 agent）。
///
/// 与 tool/smoke_ssh.dart --agent 的分工：那个脚本跑纯 Dart 的协议客户端，
/// 这里走 App 自己的传输层（createSshTransport → agent 身份 → dartssh2
/// 认证），只能在 Flutter 的测试 VM 里跑。默认**跳过**——没有本机 agent
/// 或目标主机时不拦任何人的 `flutter test`；要跑就给出目标并让测试进程
/// 的 SSH_AUTH_SOCK 指向已装入密钥的 agent：
///
/// ```
/// SSH_AUTH_SOCK=/tmp/agent.sock NOSHELL_SMOKE_HOST=192.0.2.10 \
///   flutter test test/agent_smoke_test.dart
/// ```
///
/// 可选：NOSHELL_SMOKE_USER（默认 root）、NOSHELL_SMOKE_PORT（默认 22）。
/// 不传密码：认证完全交给 agent 里的密钥。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';

final _env = Platform.environment;
final _host = _env['NOSHELL_SMOKE_HOST'];
final _agentSock = _env['SSH_AUTH_SOCK'];
final _user = _env['NOSHELL_SMOKE_USER'] ?? 'root';
final _port = int.tryParse(_env['NOSHELL_SMOKE_PORT'] ?? '') ?? 22;

/// 没给主机或本机没有 agent 就整组跳过：这是需要真机 + 真 agent 的冒烟。
final _skip = _host == null || _agentSock == null
    ? '未设置 NOSHELL_SMOKE_HOST / SSH_AUTH_SOCK，跳过 Agent 认证冒烟'
    : null;

void main() {
  test('Agent 认证：经本机 agent 连上真实主机并跑通 shell', () async {
    final server = SshServer(
      id: 'smoke-agent-target',
      group: 'smoke',
      name: 'smoke-agent-target',
      host: _host!,
      port: _port,
      username: _user,
      authMethod: AuthMethod.agent,
    );
    final session = TerminalSession(
      server: server,
      credentials: const SshCredentials(useAgent: true),
      // hostKeys 省略（null）：冒烟不做 TOFU 校验，与其他冒烟一致。
    );
    addTearDown(session.dispose);
    await session.start();
    expect(
      session.phase,
      TerminalPhase.connected,
      reason: 'Agent 认证连接失败：${session.error}',
    );

    // 在认证后的交互式 shell 里跑一条命令，证明通道真的可用。
    const marker = 'NOSHELL-AGENT-OK';
    session.terminal.textInput('echo $marker\n');
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var text = '';
    while (DateTime.now().isBefore(deadline)) {
      text = session.terminal.buffer.getText();
      if (text.contains(marker)) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect(text, contains(marker), reason: text);
    // ignore: avoid_print
    print('AGENT SMOKE PASS: $_user@$_host:$_port 经 agent 认证连上');
  }, skip: _skip);
}
