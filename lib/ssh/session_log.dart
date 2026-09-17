import 'package:xterm/core.dart';

/// 会话日志：一个会话内所有「出现在终端上的输出」的有界转录。
///
/// 只记远端输出（含回显），不记本机键盘输入：远端提示输密码时会关闭回显，
/// 输入若另行记录就会绕过这层保护、把密码明文写进日志——会话日志因此
/// 与终端画面保持同一份内容，画面上没有的日志里也没有。
final class SessionLog {
  SessionLog({int capacity = 512 * 1024})
    : _capacity = capacity > 0 ? capacity : 1;

  /// 转录最多保留的字符数；超出后丢弃最旧的内容，保住最近的。
  final int _capacity;

  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  bool get isEmpty => _buffer.isEmpty;

  void clear() {
    _buffer.clear();
  }

  /// 追加一段远端输出。超限时不逐次裁剪（那会让每次写都是一次全量拷贝），
  /// 攒到两倍容量再一次性裁回容量，摊还为均摊常数。
  void append(String data) {
    if (data.isEmpty) return;
    _buffer.write(data);
    if (_buffer.length > _capacity * 2) {
      final keep = _buffer.toString().substring(_buffer.length - _capacity);
      _buffer
        ..clear()
        ..write(keep);
    }
  }
}

/// 带转录旁路的终端：远端每写入一笔，同步落进 [SessionLog]。
///
/// 传输层持有的、传给 xterm 视图的是同一个实例，视图与日志因此天然一致。
final class LoggingTerminal extends Terminal {
  LoggingTerminal({super.maxLines});

  final SessionLog log = SessionLog();

  @override
  void write(String data) {
    super.write(data);
    log.append(data);
  }
}
