/// SSH agent 的 web 桩：浏览器里没有本机 agent 这回事。
///
/// UI 依据 [sshAgentSupported] 隐藏入口，正常流程走不到 [connectSshAgent]；
/// 万一走到（跳过 UI 直接构造 agent 凭据），抛 [UnsupportedError] 兜底。
library;

import 'ssh_agent.dart';

bool get sshAgentSupported => false;

String? get sshAgentSocketPath => null;

Future<SshAgentClient> connectSshAgent({String? socketPath}) async {
  throw UnsupportedError('SSH agent is not available on this platform');
}
