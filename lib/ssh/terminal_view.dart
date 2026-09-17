import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../settings.dart';
import '../snippets.dart';
import '../theme.dart';
import '../widgets/session_log_dialog.dart';
import '../widgets/snippet_dialog.dart';
import 'auto_reconnect.dart';
import 'terminal_session.dart';

/// 会话阶段映射为主机展示状态，复用现有的状态圆点 / 徽章。
ServerStatus serverStatusOf(TerminalPhase phase) => switch (phase) {
  TerminalPhase.connecting => ServerStatus.connecting,
  TerminalPhase.connected => ServerStatus.connected,
  TerminalPhase.failed => ServerStatus.error,
  TerminalPhase.closed => ServerStatus.idle,
};

/// 真实 SSH 终端视图：按全局偏好渲染会话缓冲区，非连接态时叠加状态浮层。
/// 右上角常驻会话工具条（命令片段 / 会话日志），挂了重连计划时浮层里
/// 会多出倒计时与「停止自动重连」。
final class SshTerminalView extends StatelessWidget {
  const SshTerminalView({
    super.key,
    required this.session,
    this.onRetry,
    this.reconnectPlan,
    this.onStopAutoReconnect,
  });

  final TerminalSession session;

  /// 失败 / 已结束时的重连动作；为空时不展示重连按钮。
  final VoidCallback? onRetry;

  /// 该会话挂着的自动重连计划；为空表示没有排队中的重连。
  final ReconnectPlan? reconnectPlan;

  /// 停止自动重连；为空时不展示停止按钮。
  final VoidCallback? onStopAutoReconnect;

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
                textStyle: _styleOf(prefs),
                padding: const EdgeInsets.all(10),
              ),
            ),
            if (phase != TerminalPhase.connected) _overlay(context, phase),
            Positioned(
              top: 6,
              right: 8,
              child: _SessionToolbar(session: session),
            ),
          ],
        );
      },
    );
  }

  /// 按偏好缓存 [TerminalStyle]。
  ///
  /// 必须缓存，不能每次 build 新建：xterm 的 `TerminalStyle` 没有
  /// `operator ==`，而它在 painter 与 render 两处的守卫都是身份比较。
  /// 新建一个内容相同的实例会一路穿过守卫，触发 `_measureCharSize()`
  /// （一次 `mmmmmmmmmm` 的 TextPainter 排版）并清空 10240 条段落缓存，
  /// 随后整个视口重排版。偏好没变就复用同一个实例。
  static TerminalStylePrefs? _cachedPrefsStyle;
  static TerminalStyle? _cachedStyle;

  static TerminalStyle _styleOf(TerminalStylePrefs prefs) {
    final cached = _cachedStyle;
    if (cached != null && _cachedPrefsStyle == prefs) return cached;
    final style = TerminalStyle(
      fontSize: prefs.fontSize.toDouble(),
      height: 1.45,
      fontFamily: prefs.resolvedFontFamily,
      fontFamilyFallback: prefs.fontFallback,
    );
    _cachedPrefsStyle = prefs;
    _cachedStyle = style;
    return style;
  }

  Widget _overlay(BuildContext context, TerminalPhase phase) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final plan = reconnectPlan;
    final message = phase == TerminalPhase.connecting
        ? l10n.connectingTo(session.server.account)
        : _failureText(l10n, phase);
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
              // 自动重连排在错误原因之后：先看到发生了什么，再看到接下来
              // 会发生什么；点「停止」后这行连同按钮一起消失，错误现场还原。
              if (plan != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.autoReconnectCountdown(
                    plan.delay.inSeconds,
                    plan.attempt,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline.withValues(alpha: 0.9),
                  ),
                ),
              ],
              if (phase != TerminalPhase.connecting && onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(l10n.reconnect),
                ),
                if (plan != null && onStopAutoReconnect != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: onStopAutoReconnect,
                    child: Text(l10n.autoReconnectStop),
                  ),
                ],
                // 指纹读不出来时不给「清除指纹」这条路：那会真的丢掉可信
                // 记录，而故障在存储层，重连或重启才是有意义的动作。
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

  String _failureText(AppLocalizations l10n, TerminalPhase phase) {
    // 干净地断开（远端关闭）不是失败原因：别把「网络错误」扣在它头上。
    if (phase == TerminalPhase.closed) return l10n.sessionClosedMsg;
    final reason = _reasonText(l10n);
    // 跳板链路上出的错必须指出是哪一跳：三台机器排在一起时，
    // 只说「认证失败」用户不知道该去改哪台的密码。
    final hop = session.failedHop;
    return hop == null ? reason : l10n.jumpHopFailure(hop, reason);
  }

  String _reasonText(AppLocalizations l10n) => switch (session.errorKind) {
    TerminalErrorKind.auth => l10n.authFailedMsg,
    TerminalErrorKind.network => l10n.networkErrorMsg,
    TerminalErrorKind.unsupported => l10n.webUnsupportedMsg,
    // 指纹带上：用户需要拿它跟服务器上的实际指纹（ssh-keygen -lf）核对，
    // 只说「不匹配」等于让人无从判断，只能盲点「清除指纹」。
    TerminalErrorKind.hostKey =>
      session.hostKeyChanged == null
          ? l10n.hostKeyChangedMsg
          : l10n.hostKeyChangedMsgWithFingerprint(
              session.hostKeyChanged!.keyType,
              session.hostKeyChanged!.fingerprint,
            ),
    TerminalErrorKind.hostKeyStore => l10n.hostKeyUnavailableMsg,
    TerminalErrorKind.privateKey => l10n.privateKeyUnsupportedMsg,
    TerminalErrorKind.agent => l10n.agentErrorMsg,
    TerminalErrorKind.jumpChain => l10n.jumpChainErrorMsg,
    TerminalErrorKind.other => session.error ?? l10n.networkErrorMsg,
  };

  /// 清除指纹后重连。指纹对不上的是跳板机上那一跳时，清的必须是那一跳的
  /// 记录（[HostKeyChangedException] 自带 host / port），否则记录原封不动、
  /// 用户点几次都还是同一个错。
  Future<void> _forgetHostKeyAndRetry() async {
    final changed = session.hostKeyChanged;
    await session.hostKeys?.delete(
      changed?.host ?? session.server.host,
      changed?.port ?? session.server.port,
    );
    onRetry?.call();
  }
}

/// 终端右上角的会话工具条：命令片段与日志查看的入口。
/// 悬浮在终端内容之上，底色用终端配色，图标对比度不随主题漂移。
final class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snippets = SnippetScope.maybeOf(context);
    // 终端样式只在「本工具条」这一小棵子树里监听：配色 / 字号变化时
    // 不连带终端视口重排。
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: TerminalStyleScope.of(context).notifier,
      builder: (context, prefs, _) {
        final foreground = prefs.theme.foreground;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: prefs.theme.background.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: foreground.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (snippets != null)
                _ToolbarButton(
                  tooltip: l10n.snippets,
                  icon: Icons.code_rounded,
                  color: foreground,
                  onTap: () => showSnippetDialog(
                    context,
                    snippets: snippets,
                    session: session,
                  ),
                ),
              _ToolbarButton(
                tooltip: l10n.sessionLog,
                icon: Icons.receipt_long_rounded,
                color: foreground,
                onTap: () => showSessionLogDialog(context, session: session),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 工具条按钮：紧凑的图标按钮，尺寸手工收紧以贴合圆角胶囊。
final class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: color),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }
}
