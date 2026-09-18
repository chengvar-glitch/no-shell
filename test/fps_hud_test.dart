// FpsMeter 的统计数学与 FpsHud 的渲染冒烟：合成 FrameTiming 喂进滑动窗口，
// 校验 fps 均值、jank 判定、窗口淘汰与空闲（无帧）语义。
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/fps_hud.dart';

/// 合成一帧：vsync 之后 1ms 开始 build，[buildUs] 完成，间隔 0.5ms 后进光栅，
/// [rasterUs] 完成。各阶段耗时段按需覆盖，默认全部远低于一帧预算。
FrameTiming _frame(
  int vsyncStartUs, {
  int buildUs = 3000,
  int rasterUs = 4000,
}) {
  final buildStart = vsyncStartUs + 1000;
  final buildFinish = buildStart + buildUs;
  final rasterStart = buildFinish + 500;
  final rasterFinish = rasterStart + rasterUs;
  return FrameTiming(
    vsyncStart: vsyncStartUs,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish + 100,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FpsMeter 统计', () {
    test('空闲（不足两帧）时 fps 为 null 而不是 0', () {
      final meter = FpsMeter(windowSize: 10);
      addTearDown(meter.dispose);
      // 不喂任何帧：引擎不会回调，fps 必须是 null（「没有帧」≠「帧很慢」）。
      expect(meter.fps, isNull);
      expect(meter.sampleCount, 0);
      expect(meter.worstSpan, isNull);
    });

    test('60Hz 均匀帧的 fps 读数约为 60', () {
      final meter = FpsMeter(windowSize: 240);
      addTearDown(meter.dispose);
      meter.debugFeed([for (var i = 0; i < 121; i++) _frame(i * 16666)]);
      expect(meter.fps, closeTo(60, 1.0));
      expect(meter.jankCount, 0);
    });

    test('jank 帧按 totalSpan 超预算计数', () {
      final meter = FpsMeter(windowSize: 240);
      addTearDown(meter.dispose);
      meter.debugFeed([
        _frame(0),
        // build 20ms：全程远超 16.6ms，必为 jank。
        _frame(16666, buildUs: 20000),
        _frame(16666 * 2),
      ]);
      expect(meter.jankCount, 1);
      expect(meter.worstSpan!.inMicroseconds, greaterThan(16600));
      expect(meter.worstBuild!.inMicroseconds, greaterThanOrEqualTo(20000));
      expect(meter.worstRaster!.inMicroseconds, 4000);
    });

    test('窗口淘汰：超过 windowSize 后只留最近 N 帧', () {
      final meter = FpsMeter(windowSize: 30);
      addTearDown(meter.dispose);
      meter.debugFeed([for (var i = 0; i < 100; i++) _frame(i * 16666)]);
      expect(meter.sampleCount, 30);
      // 仍是 60Hz 均匀帧，淘汰后均值不变。
      expect(meter.fps, closeTo(60, 1.0));
    });

    test('reset 清空窗口', () {
      final meter = FpsMeter(windowSize: 30);
      addTearDown(meter.dispose);
      meter.debugFeed([for (var i = 0; i < 10; i++) _frame(i * 16666)]);
      meter.reset();
      expect(meter.sampleCount, 0);
      expect(meter.fps, isNull);
    });
  });

  group('FpsHud 渲染', () {
    testWidgets('空闲时 FPS 显示占位 --，500ms 刷新不炸', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FpsHud())),
      );
      expect(find.textContaining('FPS --'), findsOneWidget);
      // 跨过一个刷新周期，HUD 仍稳定显示占位。
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('FPS --'), findsOneWidget);
    });

    testWidgets('注入帧数据后显示数值读数', (tester) async {
      final meter = FpsMeter(windowSize: 240);
      addTearDown(meter.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FpsHud(meter: meter)),
        ),
      );
      meter.debugFeed([for (var i = 0; i < 60; i++) _frame(i * 16666)]);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('FPS 60'), findsOneWidget);
      expect(find.textContaining('jank 0/60'), findsOneWidget);
    });
  });
}
