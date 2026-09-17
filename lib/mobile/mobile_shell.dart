import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../ssh/credential_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import 'keys_tab.dart';
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
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

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
          ),
          TerminalTab(sessions: widget.sessions),
          const KeysTab(),
          SettingsTab(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            language: widget.language,
            onLanguageChanged: widget.onLanguageChanged,
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
            icon: const Icon(Icons.key_outlined),
            selectedIcon: const Icon(Icons.key_rounded),
            label: l10n.navKeys,
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
