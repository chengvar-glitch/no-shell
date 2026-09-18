import 'package:xterm/core.dart';

/// 会话日志：终端画面（含回滚）的纯文本快照。
///
/// 取的是终端缓冲区里已经解析好的文本，而不是远端原始字节流。原始流里混着
/// 配色、窗口标题（OSC 0）、bracketed paste 等控制序列，直接落盘就是满屏
/// `]0;host:~` `[?2004h` 这类 ESC 乱码；行编辑与 `\r` 重画也会把中间态留下
/// （`downloading 10% 55%100%`）。缓冲区里没有这些问题：颜色没了，进度条只剩
/// 最终一帧，转义序列被切成两块到达也照样解析正确。
///
/// 代价是日志跟着画面走：终端里执行 `clear`、或退出全屏程序之后被抹掉的内容
/// 不会保留，与 iTerm2「保存内容」/ tmux capture-pane 同一语义。容量上限是
/// 终端的回滚行数（见 `TerminalSession.terminal` 的 `maxLines`）。
///
/// 快照与画面同源，画面上没有的日志里也没有：远端提示输密码时会关回显，
/// 密码因此进不了日志。
final class SessionLog {
  SessionLog(this._terminal);

  final Terminal _terminal;

  /// 缓冲区全文（含回滚）的纯文本，屏幕底部没写到的空行不算内容。
  String get text => _trimTrailingBlankLines(_terminal.buffer.getText());

  /// 去掉尾部整行空白：屏幕行数固定，光标下面那些行只是「还没写到的格子」。
  /// 只在末尾倒着找第一行有内容的，中间的空行（`echo; echo` 那种）原样保留。
  static String _trimTrailingBlankLines(String text) {
    final lines = text.split('\n');
    var end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    if (end == lines.length) return text;
    return lines.take(end).join('\n');
  }
}
