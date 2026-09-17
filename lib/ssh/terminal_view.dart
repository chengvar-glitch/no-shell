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
                textStyle: _styleOf(prefs),
                padding: const EdgeInsets.all(10),
              ),
            ),
            if (phase != TerminalPhase.connected) _overlay(context, phase),
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

  String _failureText(AppLocalizations l10n) {
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
