# third_party/

## xterm/

`pub.dev` 上 `xterm 4.0.0` 的副本（MIT，许可原文见 `xterm/LICENSE`），改了三处：
`lib/src/ui/custom_text_edit.dart` 里的输入去重逻辑（下详）、
`lib/src/ui/shortcut/shortcuts.dart` 里 Linux/Windows 默认键位表的 Ctrl+A、
以及拖选贴边自动滚动（`lib/src/ui/gesture/`，下详）。由根 `pubspec.yaml` 的
`dependency_overrides` 挂上，应用实际用的就是这个目录，不是 pub 上的包。

### 为什么需要这份 fork

中文这类走「预编辑」的输入法，一次上屏在 GTK 上会触发三个信号
（`commit` / `preedit-changed` / `preedit-end`），引擎把**同一个编辑状态**发三遍给框架。
上游的 `CustomTextEditState.updateEditingValue` 拿**写死的初始状态**
（`_initEditingState`）算差集：

```dart
final textDelta = _currentEditingState.text.substring(_initEditingState.text.length);
```

于是这三遍各自都把整段文字当成「新输入」交给终端，远端收到三份——
Linux 上打一个汉字出现三次。同一处逻辑在 macOS 上表现为「撇号重发」
（上游 PR [TerminalStudio/xterm.dart#226](https://github.com/TerminalStudio/xterm.dart/pull/226)，
截至写这份说明时仍未合入；它只改了非 `deleteDetection` 那条分支，而本应用此前
全平台都开着 `deleteDetection`，所以照抄它并不能修好这里）。

### 打的是什么补丁

1. **记住平台最近一次报来的文本**（`_seenText`），差集按它算，不再按写死的初始状态算：
   同一笔提交被重发时，差集为空，什么也不发；而用户真的又敲了一个同样的字，
   引擎报来的是**更长的累积文本**（因为我们不再回写初始状态），差集正好是那个新字。
   两类「重复」因此在逻辑上分得开，不靠时间去猜——终端不该吞用户输入。
2. **不再在每次输入后把平台状态重置回初始值**（`deleteDetection` 那条分支保留原行为）：
   正是这个重置与真实平台状态之间的偏差制造了重复。
3. **重新建立输入连接时把镜像也归位**：`_openInputConnection` 会把平台状态设为初始值，
   镜像不跟着归位的话，重新聚焦后第一段更短的输入会被当成「没有新内容」丢掉。

配套的仓库侧改动：`deleteDetection` 只在触屏平台打开（桌面端的退格是真实按键事件，
不需要那个两空格占位符）。

### 其余两处补丁（桌面复制体验）

1. **`shortcuts.dart`：Linux/Windows 默认键位表去掉 Ctrl+A 全选**。快捷键判定
   跑在 `terminal.keyInput` 之前，绑了全选，readline 的「回行首」（^A）就按不出
   来——没有任何主流终端绑这个。全选仍可从右键菜单走。升级回 pub 包时若上游
   仍绑着，在应用侧的 `terminalShortcuts()` 里把这条覆盖掉即可（表是整体替换）。
2. **`gesture/`：拖选贴边自动滚动**。鼠标拖选 / 触屏长按拖选到视口上下 32px
   内时，按帧（16ms）滚动一行并按原起止点重算选区——此前拖到屏幕边就停，
   选不完超过一屏的内容。滚到回滚顶 / 最新底自动停；全屏程序（alt buffer）
   不滚。配套把 `PanGestureRecognizer` 的 onEnd / onCancel 与长按抬起接进
   手势处理器，用于停掉滚动计时器。

### 怎么升级

上游修好之后：把 `third_party/xterm` 换回 pub 依赖（删掉根 `pubspec.yaml` 的
`dependency_overrides` 一段与本目录），并确认 `test/terminal_ime_test.dart` 仍全绿——
那几条用例断的正是这份补丁要保住的行为。
