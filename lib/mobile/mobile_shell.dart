import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../ssh/credential_store.dart';
import '../ssh/host_key_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
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

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ServersTab(
            store: widget.store,
            sessions: widget.sessions,
            credentials: widget.credentials,
            hostKeys: widget.hostKeys,
          ),
          TerminalTab(sessions: widget.sessions),
          // 告警依赖 store 的可读状态，且 Shell 不随 store 重建，
          // 因此在这里单独订阅一次，只在设置 Tab 一棵子树内响应。
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => SettingsTab(
              themeMode: widget.themeMode,
              onThemeModeChanged: widget.onThemeModeChanged,
              language: widget.language,
              onLanguageChanged: widget.onLanguageChanged,
              archiveUnreadable: widget.store.archiveUnreadable,
              allowLegacyHostKeys: widget.allowLegacyHostKeys,
              onAllowLegacyHostKeysChanged: widget.onAllowLegacyHostKeysChanged,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
