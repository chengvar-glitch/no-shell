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
  String get text => _trimTrailingBlankLinesText(_terminal.buffer.getText());

  /// 逐行形式（同样去掉尾部整行空白）。
  ///
  /// 弹窗按行虚拟化渲染（见 `_LogBody`），不必把整份缓冲区当成一个段落交给
  /// 单个 `Text` 排版——回滚上限是五万行，那一次排版是实打实的主线程停顿。
  ///
  /// 空快照必须给空列表：`''.split('\n')` 是 `['']` 而不是 `[]`，直接切行会
  /// 让弹窗把「一行空行」当成有内容，空态文案与按钮禁用一起失效。
  List<String> get lines => text.isEmpty ? const [] : text.split('\n');

  /// 去掉尾部整行空白：屏幕行数固定，光标下面那些行只是「还没写到的格子」。
  /// 只在末尾倒着找第一行有内容的，中间的空行（`echo; echo` 那种）原样保留。
  ///
  /// 倒着扫，不 `split('\n')`：回滚上限是五万行，切一遍再拼回去等于每次
  /// 取快照都白扔两次全量分配，而尾部空行通常只有十几行。[lines] 因此先
  /// 裁文本再切行：split 仍然只做一遍，且省掉尾部空行那一段。
  static String _trimTrailingBlankLinesText(String text) {
    var end = text.length;
    while (end > 0) {
      final start = text.lastIndexOf('\n', end - 1) + 1;
      if (text.substring(start, end).trim().isNotEmpty) break;
      if (start == 0) return '';
      // 连同这一行前面的换行一起去掉。
      end = start - 1;
    }
    return end == text.length ? text : text.substring(0, end);
  }
}
