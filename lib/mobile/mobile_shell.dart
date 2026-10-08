import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../ssh/credential_store.dart';
import '../ssh/host_key_store.dart';
import '../shell_layout.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../update_check.dart';
import '../widgets/settings_controls.dart';
import 'servers_tab.dart';
import 'settings_tab.dart';
import 'terminal_tab.dart';

/// 移动端主骨架：底部导航 + 四个 Tab，与桌面端左右分栏通过窗口宽度切换。
class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    this.hostKeys,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    this.allowLegacyHostKeys = false,
    this.onAllowLegacyHostKeysChanged,
    this.layout,
    this.updateCheck,
    this.openReleasePage,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;

  /// 已记录的主机指纹；删除主机时一并清理，可选（测试可省）。
  final HostKeyStore? hostKeys;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// 连接老设备时是否允许 ssh-rsa（SHA-1）主机密钥。
  final bool allowLegacyHostKeys;
  final ValueChanged<bool>? onAllowLegacyHostKeysChanged;

  /// 跨断点保留的界面状态；由应用入口持有，两套骨架共用一份。
  /// 为空时（组件测试、单独挂载）本页自建一份，行为与从前一致。
  final ShellLayoutState? layout;

  /// 版本检测；为 null 时不显示更新入口，底部设置 Tab 也不挂红点。
  final UpdateCheckService? updateCheck;

  /// 打开发布页的能力；不传时走系统实现。
  final Future<bool> Function(Uri uri)? openReleasePage;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  /// 当前 Tab 放在共享状态里：窗口宽度跨过断点时整套骨架会被换掉，
  /// 留在 State 里就会跳回第一个 Tab。
  late final ShellLayoutState _layout = widget.layout ?? ShellLayoutState();

  /// 底部 Tab 切换：先给一次触感反馈再换页。
  ///
  /// 触感走系统通道 `HapticFeedback.selectionClick()`——Android 落到
  /// `HapticFeedbackConstants.CLOCK_TICK`（振动马达轻敲一下），iOS 落到
  /// `UISelectionFeedbackGenerator`（Taptic Engine）。它正是「选择变更」这一类
  /// 反馈，不引第三方依赖，Android 也不需要 `VIBRATE` 权限；平台不支持时
  /// 通道是 OptionalMethodChannel，静默无操作（web / Linux / Windows）。
  void _onTabSelected(int index) {
    // 重复点当前 Tab 并没有发生选择变更，不该再振一下。
    if (index == _layout.tab) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _layout.tab = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _layout.tab,
        children: [
          ServersTab(
            store: widget.store,
            sessions: widget.sessions,
            credentials: widget.credentials,
            hostKeys: widget.hostKeys,
          ),
          TerminalTab(
            sessions: widget.sessions,
            credentials: widget.credentials,
          ),
          // 告警依赖 store 的可读状态，且 Shell 不随 store 重建。订阅只包住
          // 告警卡自己：SettingsTab 常驻 IndexedStack，整棵包住的话每次主机
          // 状态翻转（连接 / 断开都会 notify）都会重排整页设置控件。
          SettingsTab(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            language: widget.language,
            onLanguageChanged: widget.onLanguageChanged,
            allowLegacyHostKeys: widget.allowLegacyHostKeys,
            onAllowLegacyHostKeysChanged: widget.onAllowLegacyHostKeysChanged,
            updateCheck: widget.updateCheck,
            openReleasePage: widget.openReleasePage,
            archiveWarning: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => widget.store.archiveUnreadable
                  ? const ArchiveWarningCard()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _layout.tab,
        onDestinationSelected: _onTabSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dns_outlined),
            selectedIcon: const Icon(Icons.dns_rounded),
            label: l10n.navServers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.terminal_outlined),
            selectedIcon: const Icon(Icons.terminal_rounded),
            label: l10n.terminal,
          ),
          NavigationDestination(
            icon: _SettingsNavIcon(
              icon: Icons.settings_outlined,
              updateCheck: widget.updateCheck,
            ),
            selectedIcon: _SettingsNavIcon(
              icon: Icons.settings_rounded,
              updateCheck: widget.updateCheck,
            ),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

/// 设置 Tab 图标：有新版本时右上角挂一个红点，并且**只订阅检测状态**——
/// 整条底部导航不该因为一次版本查询重建。
class _SettingsNavIcon extends StatelessWidget {
  const _SettingsNavIcon({required this.icon, this.updateCheck});

  final IconData icon;
  final UpdateCheckService? updateCheck;

  @override
  Widget build(BuildContext context) {
    final service = updateCheck;
    if (service == null) return Icon(icon);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          if (service.updateAvailable)
            const Positioned(
              right: -2,
              top: -2,
              child: UpdateAvailableDot(size: 8),
            ),
        ],
      ),
    );
  }
}
