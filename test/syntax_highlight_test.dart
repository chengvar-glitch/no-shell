import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/syntax_highlight.dart';

Iterable<TextSpan> _leafSpans(Iterable<TextSpan> spans) sync* {
  for (final span in spans) {
    if (span.children == null) {
      yield span;
      continue;
    }
    yield* _leafSpans(span.children!.cast<TextSpan>());
  }
}

String _text(Iterable<TextSpan> spans) =>
    spans.map((span) => span.text ?? '').join();

void main() {
  group('syntaxHighlightLanguage', () {
    test('按扩展名映射常用语言，未知类型不高亮', () {
      expect(syntaxHighlightLanguage('main.dart'), 'dart');
      expect(syntaxHighlightLanguage('SCRIPT.SH'), 'shell');
      expect(syntaxHighlightLanguage('styles.css'), 'css');
      expect(syntaxHighlightLanguage('Makefile'), isNull);
      expect(syntaxHighlightLanguage('notes.txt'), isNull);
      expect(syntaxHighlightLanguage('.env'), 'shell');
    });
  });

  group('highlightSyntaxLines', () {
    test('按行拆分 token 并给关键字 / 字符串 / 注释上色', () {
      final lines = highlightSyntaxLines(
        'final name = "world";\n// done',
        'dart',
      );

      expect(lines, hasLength(2));
      final first = _leafSpans(lines[0]).toList();
      final keyword = first.singleWhere((span) => span.text == 'final');
      final string = first.singleWhere((span) => span.text == '"world"');
      final comment = _leafSpans(lines[1]).single;

      expect(keyword.style?.color, const Color(0xFFC678DD));
      expect(string.style?.color, const Color(0xFF98C379));
      expect(comment.text, '// done');
      expect(comment.style?.color, const Color(0xFF8B949E));
    });

    test('浅色主题换用白底高亮色', () {
      final lines = highlightSyntaxLines(
        'final name = "world";\n// done',
        'dart',
        brightness: Brightness.light,
      );

      final first = _leafSpans(lines[0]).toList();
      final keyword = first.singleWhere((span) => span.text == 'final');
      final string = first.singleWhere((span) => span.text == '"world"');
      final comment = _leafSpans(lines[1]).single;

      expect(keyword.style?.color, const Color(0xFFCF222E));
      expect(string.style?.color, const Color(0xFF0A3069));
      expect(comment.style?.color, const Color(0xFF6E7781));
    });

    test('保留空行，超长行切成多个懒构建块', () {
      final longLine = '${'a' * 2048}tail';
      final lines = highlightSyntaxLines('$longLine\n\n', 'javascript');

      expect(lines, hasLength(3));
      expect(_text(lines[0]), longLine);
      expect(lines[0].first.text!.length, 2048);
      expect(lines[0].last.text, 'tail');
      expect(lines[1], isEmpty);
      expect(lines[2], isEmpty);
    });
  });
}
