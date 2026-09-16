import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import 'terminal_session.dart';

/// 会话阶段映射为主机展示状态，复用现有的状态圆点 / 徽章。
ServerStatus serverStatusOf(TerminalPhase phase) => switch (phase) {
  TerminalPhase.connecting => ServerStatus.connecting,
  TerminalPhase.connected => ServerStatus.connected,
  TerminalPhase.failed => ServerStatus.error,
  TerminalPhase.closed => ServerStatus.idle,
};

/// 真实 SSH 终端视图：按全局偏好渲染会话缓冲区，非连接态时叠加状态浮层。
final class SshTerminalView extends StatelessWidget {
  const SshTerminalView({super.key, required this.session, this.onRetry});

  final TerminalSession session;

  /// 失败 / 已结束时的重连动作；为空时不展示重连按钮。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final phase = session.phase;
    // 只监听终端样式偏好：切换预设 / 字体时仅终端区域重建。
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: TerminalStyleScope.of(context).notifier,
      builder: (context, prefs, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: TerminalView(
                session.terminal,
                theme: prefs.theme,
                autofocus: true,
                // 移动端软键盘的删除键不走硬件按键事件，需要开启检测。
                deleteDetection: true,
                textStyle: TerminalStyle(
                  fontSize: prefs.fontSize.toDouble(),
                  height: 1.45,
                  fontFamily: prefs.resolvedFontFamily,
                  fontFamilyFallback: prefs.fontFallback,
                ),
                padding: const EdgeInsets.all(10),
              ),
            ),
            if (phase != TerminalPhase.connected) _overlay(context, phase),
          ],
        );
      },
    );
  }

  Widget _overlay(BuildContext context, TerminalPhase phase) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final message = phase == TerminalPhase.connecting
        ? l10n.connectingTo(session.server.account)
        : _failureText(l10n);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC0A0C0F),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phase == TerminalPhase.connecting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                Icon(
                  phase == TerminalPhase.failed
                      ? Icons.error_outline_rounded
                      : Icons.link_off_rounded,
                  size: 34,
                  color: phase == TerminalPhase.failed
                      ? AppPalette.danger
                      : theme.colorScheme.outline,
                ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFFB9C4CF),
                ),
              ),
              if (phase != TerminalPhase.connecting && onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(l10n.reconnect),
                ),
                // 密钥变更拒绝时额外提供处置入口：用户确认服务器确实更换后，
                // 清掉旧指纹重新走首次记录流程；这是显式动作，不自动放行。
                if (phase == TerminalPhase.failed &&
                    session.errorKind == TerminalErrorKind.hostKey &&
                    session.hostKeys != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _forgetHostKeyAndRetry,
                    icon: const Icon(Icons.key_off_rounded, size: 17),
                    label: Text(l10n.hostKeyForgetAndRetry),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _failureText(AppLocalizations l10n) => switch (session.errorKind) {
    TerminalErrorKind.auth => l10n.authFailedMsg,
    TerminalErrorKind.network => l10n.networkErrorMsg,
    TerminalErrorKind.unsupported => l10n.webUnsupportedMsg,
    TerminalErrorKind.hostKey => l10n.hostKeyChangedMsg,
    TerminalErrorKind.other => session.error ?? l10n.networkErrorMsg,
  };

  Future<void> _forgetHostKeyAndRetry() async {
    await session.hostKeys?.delete(session.server.host, session.server.port);
    onRetry?.call();
  }
}
