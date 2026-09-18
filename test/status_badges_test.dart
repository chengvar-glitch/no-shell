import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/status_badges.dart';

/// WCAG 相对亮度（[Color] 的分量已是 0..1）。
double _luminance(Color color) {
  double linear(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// 两色的 WCAG 对比度（1:1 ~ 21:1）。
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // 胶囊里是 11px 半粗小字，按 WCAG AA 的小字门槛 4.5:1 要求。
  // 底色是 13% 半透明的状态色，得先垫在页面底色上再算对比。
  group('状态胶囊文字对比度', () {
    final themes = {'浅色': AppTheme.light(), '深色': AppTheme.dark()};

    for (final entry in themes.entries) {
      for (final status in ServerStatus.values) {
        test('${entry.key}主题 · ${status.name} ≥ 4.5:1', () {
          final palette = pillColors(entry.value, status);
          final backdrop = Color.alphaBlend(
            palette.background,
            AppColors.of(entry.value.brightness).pageBackground,
          );
          expect(
            _contrast(palette.foreground, backdrop),
            greaterThanOrEqualTo(4.5),
            reason: '文字 ${palette.foreground} 压在底色 $backdrop 上太淡了',
          );
        });
      }
    }

    test('四态的文字色互不相同，没退化成同一个灰', () {
      final theme = AppTheme.light();
      final colors = {
        for (final status in ServerStatus.values)
          status: pillColors(theme, status).foreground,
      };
      expect(colors.values.toSet(), hasLength(ServerStatus.values.length));
    });
  });

  group('StatusPill', () {
    Future<void> pump(WidgetTester tester, Widget pill) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: pill)),
      ),
    );

    testWidgets('单会话：只有状态文案，没有计数与箭头', (tester) async {
      await pump(
        tester,
        const StatusPill(status: ServerStatus.connected, sessionCount: 1),
      );

      expect(find.text('已连接'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(tester.getSize(find.byType(StatusPill)).height, 24);
    });

    testWidgets('多会话：文案带计数，箭头与文字同色', (tester) async {
      await pump(
        tester,
        const StatusPill(status: ServerStatus.connected, sessionCount: 3),
      );

      expect(find.text('已连接 · 3'), findsOneWidget);
      final arrow = tester.widget<Icon>(find.byIcon(Icons.expand_more_rounded));
      final palette = pillColors(AppTheme.light(), ServerStatus.connected);
      expect(arrow.color, palette.foreground);
      // 箭头比文字还重就会抢注意力：11pt 已比文字的 11px 视觉重量低一档。
      expect(arrow.size, 11);
    });
  });
}
