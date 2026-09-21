import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' show Highlight, Node;
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/ini.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/properties.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/shell.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

/// 只登记 SFTP 预览会碰到的语言。`highlight` 包的默认单例会登记全部
/// 语言；这里单独建实例，让启动成本和二进制体积只覆盖常用子集。
final Highlight _highlighter = Highlight()
  ..registerLanguages({
    'cpp': cpp,
    'css': css,
    'dart': dart,
    'go': go,
    'ini': ini,
    'java': java,
    'javascript': javascript,
    'json': json,
    'markdown': markdown,
    'php': php,
    'properties': properties,
    'python': python,
    'ruby': ruby,
    'rust': rust,
    'shell': shell,
    'sql': sql,
    'typescript': typescript,
    'xml': xml,
    'yaml': yaml,
  });

/// 超过这个字节数不跑语法解析。预览允许到 256 MB，语法高亮不能把
/// 「看得一眼」变成一次整文件的解析、排版和内存放大；大文件仍保持纯文本。
const int kSyntaxHighlightMaxBytes = 1024 * 1024;

/// 扩展名 → highlight 语言的窄映射。没列出的预览文本（日志、txt、
/// 未知配置）继续走纯文本；宁可不高亮，也不拿错误语言去猜。
const Map<String, String> _kSyntaxHighlightLanguages = {
  'bash': 'shell',
  'c': 'cpp',
  'cfg': 'ini',
  'conf': 'ini',
  'cpp': 'cpp',
  'css': 'css',
  'dart': 'dart',
  'env': 'shell',
  'go': 'go',
  'h': 'cpp',
  'htm': 'xml',
  'html': 'xml',
  'ini': 'ini',
  'java': 'java',
  'js': 'javascript',
  'json': 'json',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'md': 'markdown',
  'php': 'php',
  'properties': 'properties',
  'py': 'python',
  'rb': 'ruby',
  'rs': 'rust',
  'sh': 'shell',
  'sql': 'sql',
  'toml': 'ini',
  'ts': 'typescript',
  'tsx': 'typescript',
  'xml': 'xml',
  'yaml': 'yaml',
  'yml': 'yaml',
  'zsh': 'shell',
};

/// 根据文件名取高亮语言；未知类型返回 null，由调用方回落纯文本。
String? syntaxHighlightLanguage(String fileName) {
  final dot = fileName.lastIndexOf('.');
  // .env 这类整名就是扩展名的文件也要能高亮；空名仍不走这里。
  if (dot < 0 || dot == fileName.length - 1) return null;
  final extension = fileName.substring(dot + 1).toLowerCase();
  return _kSyntaxHighlightLanguages[extension];
}

/// 预览深底上的高亮色。颜色取自常见暗色主题的家族，但背景交给
/// SFTP 预览自己的半透明层；高亮层只负责字色和少量斜体 / 粗体。
const Map<String, TextStyle> _kSyntaxTheme = {
  'addition': TextStyle(color: Color(0xFF98C379)),
  'attr': TextStyle(color: Color(0xFFD19A66)),
  'attribute': TextStyle(color: Color(0xFFD19A66)),
  'built_in': TextStyle(color: Color(0xFFE5C07B)),
  'bullet': TextStyle(color: Color(0xFF61AFEF)),
  'comment': TextStyle(color: Color(0xFF8B949E), fontStyle: FontStyle.italic),
  'deletion': TextStyle(color: Color(0xFFE06C75)),
  'doctag': TextStyle(color: Color(0xFFC678DD)),
  'formula': TextStyle(color: Color(0xFFC678DD)),
  'keyword': TextStyle(color: Color(0xFFC678DD)),
  'link': TextStyle(color: Color(0xFF61AFEF)),
  'literal': TextStyle(color: Color(0xFF56B6C2)),
  'meta': TextStyle(color: Color(0xFF61AFEF)),
  'meta-string': TextStyle(color: Color(0xFF98C379)),
  'name': TextStyle(color: Color(0xFFE06C75)),
  'number': TextStyle(color: Color(0xFFD19A66)),
  'operator': TextStyle(color: Color(0xFF56B6C2)),
  'quote': TextStyle(color: Color(0xFF8B949E), fontStyle: FontStyle.italic),
  'regexp': TextStyle(color: Color(0xFF98C379)),
  'section': TextStyle(color: Color(0xFF61AFEF), fontWeight: FontWeight.bold),
  'selector-attr': TextStyle(color: Color(0xFFD19A66)),
  'selector-class': TextStyle(color: Color(0xFFE5C07B)),
  'selector-id': TextStyle(color: Color(0xFF61AFEF)),
  'selector-pseudo': TextStyle(color: Color(0xFFD19A66)),
  'selector-tag': TextStyle(color: Color(0xFFE06C75)),
  'string': TextStyle(color: Color(0xFF98C379)),
  'subst': TextStyle(color: Color(0xFFABB2BF)),
  'symbol': TextStyle(color: Color(0xFF61AFEF)),
  'tag': TextStyle(color: Color(0xFFE06C75)),
  'template-variable': TextStyle(color: Color(0xFFD19A66)),
  'title': TextStyle(color: Color(0xFF61AFEF)),
  'type': TextStyle(color: Color(0xFFE5C07B)),
  'variable': TextStyle(color: Color(0xFFD19A66)),
};

/// 把源码解析成“每一行一组叶子 [TextSpan]”。
///
/// 语法结构会跨行（块注释、多行字符串），所以必须先整篇解析再按行摊平；
/// 反过来逐行解析会把 ```dart\nfoo\n``` 这类结构拆碎。这里只返回叶子
/// span，后续按 UTF-16 码元切块时就不必再遍历嵌套树。
List<List<TextSpan>> highlightSyntaxLines(String source, String language) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.isEmpty) return const <List<TextSpan>>[<TextSpan>[]];
  try {
    final result = _highlighter.parse(normalized, language: language);
    final lines = <List<TextSpan>>[<TextSpan>[]];
    if (result.nodes == null) return lines;
    for (final node in result.nodes!) {
      _visitSyntaxNode(node, _kSyntaxTheme['subst'], lines);
    }
    return [for (final line in lines) _splitSyntaxPreviewLine(line)];
  } on FormatException {
    // highlight 的语言规则由包内置；遇到解析器不接受的内容时，预览不能消失。
    return <List<TextSpan>>[
      for (final line in normalized.split('\n')) [TextSpan(text: line)],
    ];
  } on ArgumentError {
    return <List<TextSpan>>[
      for (final line in normalized.split('\n')) [TextSpan(text: line)],
    ];
  }
}

void _visitSyntaxNode(
  Node node,
  TextStyle? parentStyle,
  List<List<TextSpan>> lines,
) {
  final style = node.className == null
      ? parentStyle
      : (_kSyntaxTheme[node.className!] ?? parentStyle);
  final value = node.value;
  if (value != null) {
    _appendSyntaxText(value, style, lines);
    return;
  }
  final children = node.children;
  if (children == null) return;
  for (final child in children) {
    _visitSyntaxNode(child, style, lines);
  }
}

void _appendSyntaxText(
  String text,
  TextStyle? style,
  List<List<TextSpan>> lines,
) {
  final segments = text.split('\n');
  for (var i = 0; i < segments.length; i++) {
    _appendSyntaxSegment(segments[i], style, lines.last);
    if (i + 1 < segments.length) lines.add(<TextSpan>[]);
  }
}

void _appendSyntaxSegment(String text, TextStyle? style, List<TextSpan> spans) {
  if (text.isEmpty) return;
  final last = spans.isEmpty ? null : spans.last;
  if (last != null && last.style == style) {
    spans[spans.length - 1] = TextSpan(text: last.text! + text, style: style);
    return;
  }
  spans.add(TextSpan(text: text, style: style));
}

/// 超长物理行按 UTF-16 码元切开。与纯文本预览同一条规则：minified
/// JSON 的一行不能变成一个极宽的语义行，否则 ListView 懒构建失效。
List<TextSpan> _splitSyntaxPreviewLine(List<TextSpan> spans) {
  const maxLength = 2048;
  if (spans.fold(0, (length, span) => length + span.text!.length) <=
      maxLength) {
    return spans;
  }

  final chunks = <TextSpan>[];
  var buffer = StringBuffer();
  TextStyle? bufferStyle;

  void flush() {
    if (buffer.isNotEmpty) {
      chunks.add(TextSpan(text: buffer.toString(), style: bufferStyle));
      buffer = StringBuffer();
      bufferStyle = null;
    }
  }

  for (final span in spans) {
    final style = span.style;
    var start = 0;
    while (start < span.text!.length) {
      if (buffer.isNotEmpty && buffer.length >= maxLength) flush();
      final available = maxLength - buffer.length;
      final end = start + available > span.text!.length
          ? span.text!.length
          : start + available;
      final piece = span.text!.substring(start, end);
      if (bufferStyle != style) {
        flush();
        buffer.write(piece);
        bufferStyle = style;
      } else {
        buffer.write(piece);
      }
      start = end;
    }
  }
  flush();
  return chunks;
}
