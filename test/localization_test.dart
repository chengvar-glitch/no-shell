import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/app_locale.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/store.dart';

import 'support/demo_servers.dart';

void main() {
  group('AppLanguage', () {
    test('跟随系统映射为 null locale，交由框架按系统语言解析', () {
      expect(AppLanguage.system.locale, isNull);
      expect(AppLanguage.chinese.locale, const Locale('zh'));
      expect(AppLanguage.english.locale, const Locale('en'));
    });

    test('选项文案不随界面语言翻译', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      expect(AppLanguage.chinese.label(en), '中文');
      expect(AppLanguage.chinese.label(zh), '中文');
      expect(AppLanguage.english.label(en), 'English');
      expect(AppLanguage.english.label(zh), 'English');
    });
  });

  group('formatRelativeTime', () {
    test('en/zh 输出对应语言', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      expect(formatRelativeTime(en, null), 'Never connected');
      expect(formatRelativeTime(zh, null), '从未连接');
      expect(formatRelativeTime(en, DateTime.now()), 'Just now');
      expect(formatRelativeTime(zh, DateTime.now()), '刚刚');
    });

    test('复数规则', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      expect(
        formatRelativeTime(
          en,
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        '1 minute ago',
      );
      expect(
        formatRelativeTime(
          en,
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        '5 minutes ago',
      );
      expect(
        formatRelativeTime(
          zh,
          DateTime.now().subtract(const Duration(hours: 3)),
        ),
        '3 小时前',
      );
      expect(
        formatRelativeTime(
          zh,
          DateTime.now().subtract(const Duration(days: 2)),
        ),
        '2 天前',
      );
    });
  });

  group('NoShellApp 语言解析与切换', () {
    // 宿主机 locale 会混入测试环境的默认 locales 列表，
    // 必须整体替换为受控列表，模拟「系统语言」。
    void useSystemLocale(WidgetTester tester, Iterable<Locale> locales) {
      tester.platformDispatcher.localesTestValue = List.of(locales);
    }

    void resetLocale(WidgetTester tester) {
      tester.platformDispatcher.clearAllTestValues();
    }

    testWidgets('zh 系统语言显示中文，en/不支持的语言回退英文', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => resetLocale(tester));

      // zh → 中文界面（侧边栏主机计数）。
      useSystemLocale(tester, const [Locale('zh')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('8 台主机'), findsOneWidget);

      // en → 英文界面。
      useSystemLocale(tester, const [Locale('en')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('8 hosts'), findsOneWidget);

      // 不支持的语言（fr）→ 回退首个支持语言英文。
      useSystemLocale(tester, const [Locale('fr')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('8 hosts'), findsOneWidget);

      // 优先匹配：zh_CN 列表命中中文。
      useSystemLocale(tester, const [Locale('zh'), Locale('en')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('8 台主机'), findsOneWidget);
    });

    testWidgets('应用内手动切换语言（设置弹窗）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => resetLocale(tester));
      useSystemLocale(tester, const [Locale('en')]);

      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('8 hosts'), findsOneWidget);

      // 语言选择搬进了设置弹窗：底部设置入口 → 语言分段。
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('中文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('8 台主机'), findsOneWidget);

      // 再进去切回 English。
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('8 hosts'), findsOneWidget);
    });

    testWidgets('移动端窄屏走底部导航且文案随语言切换', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => resetLocale(tester));

      useSystemLocale(tester, const [Locale('en')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Servers'), findsWidgets);

      useSystemLocale(tester, const [Locale('zh')]);
      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务器'), findsWidgets);
    });
  });
}
