import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/main.dart';

void main() {
  const preferred = kDesktopPreferredWindowSize;
  const minimum = kDesktopMinimumWindowSize;

  test('偏好尺寸为旧版 1280x720 的 120%', () {
    expect(preferred, const Size(1536, 864));
    expect(minimum, const Size(940, 600));
  });

  test('大屏保持偏好尺寸与最小尺寸', () {
    final bounds = resolveDesktopWindowSize(
      preferred: preferred,
      minimum: minimum,
      screen: const Size(2560, 1440),
    );

    expect(bounds.size, preferred);
    expect(bounds.minimum, minimum);
  });

  test('低分辨率屏幕按可用区域收缩并留边', () {
    final bounds = resolveDesktopWindowSize(
      preferred: preferred,
      minimum: minimum,
      screen: const Size(1366, 768),
    );

    expect(bounds.size, const Size(1366 - 32, 768 - 32));
    expect(bounds.minimum, minimum);
  });

  test('屏幕小于最小尺寸时最小尺寸同步收缩', () {
    final bounds = resolveDesktopWindowSize(
      preferred: preferred,
      minimum: minimum,
      screen: const Size(800, 600),
    );

    expect(bounds.size, const Size(768, 568));
    expect(bounds.minimum, bounds.size);
  });

  test('拿不到屏幕信息时不做裁剪', () {
    for (final screen in <Size?>[null, Size.zero, const Size(-1, 0)]) {
      final bounds = resolveDesktopWindowSize(
        preferred: preferred,
        minimum: minimum,
        screen: screen,
      );

      expect(bounds.size, preferred);
      expect(bounds.minimum, minimum);
    }
  });
}
