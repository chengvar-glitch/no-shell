part of 'sftp_browser.dart';

/// 预览外的背景轻微压暗；预览本体再用深色半透明底承载。
/// 叠加后下层界面保留约 29% 透出度：能感觉到上下文，又不干扰读图。
const double kSftpPreviewScrimOpacity = 0.28;
const double kSftpPreviewSurfaceOpacity = 0.62;

Color _previewSurfaceColor() =>
    Colors.black.withValues(alpha: kSftpPreviewSurfaceOpacity);

/// 超长行按 UTF-16 码元分块后再交给 Flutter 文本布局。
/// 一个 16 MB 的 minified JSON 如果作为单个 Text 布局，会造出极宽的
/// 语义行；分块让 ListView 继续懒构建，也避免横向布局撑爆。
const int _kTextPreviewChunkLength = 2048;

/// 快速预览的类型。
enum SftpQuickPreviewKind { image, text }

/// 预览关闭结果；`tooLarge` 由外层接回原有下载链路。
enum SftpQuickPreviewOutcome { canceled, tooLarge }

/// Flutter 引擎直接可解码的常见位图；SVG 由已有 flutter_svg 处理。
/// ICO 的多尺寸容器不值得为预览单独引入解码器。
const Set<String> _kImagePreviewExtensions = {
  'bmp',
  'gif',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'webp',
};

/// 常见纯文本 / 源码 / 配置扩展名。只按扩展名粗判；
/// 扩展名误判的二进制在读取后由 NUL 字节启发式挡住。
const Set<String> _kTextPreviewExtensions = {
  'bash',
  'c',
  'cfg',
  'conf',
  'cpp',
  'css',
  'dart',
  'env',
  'go',
  'h',
  'htm',
  'html',
  'ini',
  'java',
  'js',
  'json',
  'jsx',
  'log',
  'mjs',
  'md',
  'php',
  'properties',
  'py',
  'rb',
  'rs',
  'sh',
  'sql',
  'toml',
  'ts',
  'tsx',
  'txt',
  'xml',
  'yaml',
  'yml',
  'zsh',
};

/// 能否走内置快速预览；返回 null 表示继续沿用原有下载入口。
SftpQuickPreviewKind? sftpQuickPreviewKind(SftpEntry entry) {
  if (entry.isDirectory) return null;
  final dot = entry.name.lastIndexOf('.');
  if (dot <= 0) return null;
  final extension = entry.name.substring(dot + 1).toLowerCase();
  if (_kImagePreviewExtensions.contains(extension)) {
    return SftpQuickPreviewKind.image;
  }
  if (_kTextPreviewExtensions.contains(extension)) {
    return SftpQuickPreviewKind.text;
  }
  return null;
}

/// 是否能走内置快速预览；只做扩展名粗判，坏文件由解码 / 解码器错误兜底。
bool isSftpQuickPreviewCandidate(SftpEntry entry) =>
    sftpQuickPreviewKind(entry) != null;

/// 打开全屏快速预览；字节只留在内存，不落用户可见目录。
/// 若已知大小或读取途中超过预算，返回 `tooLarge`，调用方接回下载流程。
Future<SftpQuickPreviewOutcome> showSftpQuickPreview(
  BuildContext context,
  SftpBrowserController controller,
  SftpEntry entry,
) async {
  // 路由还没建立时先取出当前档位：预览打开后它就固定为本次请求的预算。
  final maxBytes = QuickPreviewLimitScope.notifierOf(context).value.bytes;
  // 列表 stat 已给出大小：超限时不闪一帧预览，直接让原有下载入口接管。
  if (entry.size > maxBytes) return SftpQuickPreviewOutcome.tooLarge;
  final kind = sftpQuickPreviewKind(entry)!;
  final result = await showDialog<SftpQuickPreviewOutcome>(
    context: context,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: kSftpPreviewScrimOpacity),
    builder: (_) => _SftpQuickPreviewDialog(
      controller: controller,
      entry: entry,
      kind: kind,
      maxBytes: maxBytes,
    ),
  );
  return result ?? SftpQuickPreviewOutcome.canceled;
}

final class _SftpQuickPreviewDialog extends StatefulWidget {
  const _SftpQuickPreviewDialog({
    required this.controller,
    required this.entry,
    required this.kind,
    required this.maxBytes,
  });

  final SftpBrowserController controller;
  final SftpEntry entry;

  final SftpQuickPreviewKind kind;

  final int maxBytes;

  @override
  State<_SftpQuickPreviewDialog> createState() =>
      _SftpQuickPreviewDialogState();
}

class _SftpQuickPreviewDialogState extends State<_SftpQuickPreviewDialog> {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _subscription;
  Uint8List? _data;
  List<String> _textLines = const [];
  bool _textLoaded = false;
  Object? _error;

  bool get _isSvg {
    return widget.kind == SftpQuickPreviewKind.image &&
        widget.entry.name.toLowerCase().endsWith('.svg');
  }

  @override
  void initState() {
    super.initState();
    // 微任务里再订阅，避免 initState 期间 setState；正常路径几乎不会走到。
    scheduleMicrotask(_load);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  void _load() {
    if (!mounted || _subscription != null || _data != null || _error != null) {
      return;
    }
    _bytes.clear();
    _subscription = widget.controller
        .readRemoteFile(widget.entry.path)
        .listen(
          (chunk) {
            if (!mounted) return;
            _bytes.add(chunk);
            // 流的已知大小可能不可靠，这里仍按实际字节兜底。
            if (_bytes.length > widget.maxBytes) {
              _stopForTooLarge();
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _error = error);
          },
          onDone: () {
            if (!mounted) return;
            _finishReading(_bytes.takeBytes());
          },
        );
  }

  void _finishReading(Uint8List data) {
    if (widget.kind == SftpQuickPreviewKind.text && data.contains(0)) {
      setState(() => _error = const FormatException('binary content'));
      return;
    }
    if (widget.kind == SftpQuickPreviewKind.text) {
      final text = utf8.decode(data, allowMalformed: true);
      setState(() {
        _textLines = _splitTextPreviewLines(text);
        _textLoaded = true;
      });
      return;
    }
    setState(() => _data = data);
  }

  void _stopForTooLarge() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _bytes.clear();
    // 预览层立刻收掉，由调用方接回“另存为 → 下载”这条既有链路。
    Navigator.of(context).pop(SftpQuickPreviewOutcome.tooLarge);
  }

  String _errorText(Object error) {
    final l10n = AppLocalizations.of(context);
    if (error is SftpException) return _sftpErrorText(l10n, error);
    return l10n.sftpPreviewInvalid;
  }

  Widget _image() {
    final data = _data!;
    final placeholderColor = Theme.of(context).colorScheme.onSurfaceVariant;
    if (_isSvg) {
      return SvgPicture.memory(
        data,
        fit: BoxFit.contain,
        placeholderBuilder: (context) =>
            ColoredBox(color: placeholderColor.withValues(alpha: .12)),
        errorBuilder: (_, _, _) => _InvalidPreview(
          message: AppLocalizations.of(context).sftpPreviewInvalid,
        ),
      );
    }
    return Image.memory(
      data,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _InvalidPreview(
        message: AppLocalizations.of(context).sftpPreviewInvalid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final surfaceColor = _previewSurfaceColor();
    final isLoading = widget.kind == SftpQuickPreviewKind.text
        ? !_textLoaded
        : _data == null;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Scaffold(
        backgroundColor: surfaceColor,
        appBar: AppBar(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          // macOS 的红绿灯浮在全屏路由 AppBar 上：加宽 leading 槽位，
          // 让自动返回箭头从灯组右侧开始；Windows/Linux 的标题栏
          // 不浮在内容上，保持 Flutter 默认位置。
          leadingWidth: usesFloatingTrafficLights
              ? kMacOSTrafficLightsLeadingWidth
              : null,
          title: Text(widget.entry.name),
        ),
        body: Center(
          child: _error != null
              ? _InvalidPreview(
                  message: _errorText(_error ?? StateError('preview failed')),
                )
              : isLoading
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        l10n.sftpPreviewLoading,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : widget.kind == SftpQuickPreviewKind.text
              ? _TextPreviewBody(lines: _textLines)
              : RepaintBoundary(
                  child: InteractiveViewer(
                    maxScale: 12,
                    child: Center(child: _image()),
                  ),
                ),
        ),
      ),
    );
  }
}

final class _TextPreviewBody extends StatelessWidget {
  const _TextPreviewBody({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).sftpPreviewEmpty,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
      );
    }
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: lines.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            lines[index],
            softWrap: true,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 物理行切成懒构建的小块；块边界不拆 UTF-16 代理对。
List<String> _splitTextPreviewLines(String text) {
  final chunks = <String>[];
  for (var line in text.split('\n')) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.length <= _kTextPreviewChunkLength) {
      chunks.add(line);
      continue;
    }
    for (var start = 0; start < line.length;) {
      var end = math.min(start + _kTextPreviewChunkLength, line.length);
      final previous = line.codeUnitAt(end - 1);
      if (end < line.length) {
        final next = line.codeUnitAt(end);
        final surrogatePair =
            previous >= 0xD800 &&
            previous <= 0xDBFF &&
            next >= 0xDC00 &&
            next <= 0xDFFF;
        // end 正好停在高代理后：把低代理一起放进这一块，避免拆散字符。
        if (surrogatePair) end++;
      }
      if (end == start) end = start + 1;
      chunks.add(line.substring(start, end));
      start = end;
    }
  }
  return chunks;
}

final class _InvalidPreview extends StatelessWidget {
  const _InvalidPreview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 40,
            color: Colors.white.withValues(alpha: 0.72),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
