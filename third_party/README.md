# third_party/

## xterm/

`pub.dev` 上 `xterm 4.0.0` 的副本（MIT，许可原文见 `xterm/LICENSE`），只改了一处：
`lib/src/ui/custom_text_edit.dart` 里的输入去重逻辑。由根 `pubspec.yaml` 的
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

### 怎么升级

上游修好之后：把 `third_party/xterm` 换回 pub 依赖（删掉根 `pubspec.yaml` 的
`dependency_overrides` 一段与本目录），并确认 `test/terminal_ime_test.dart` 仍全绿——
那几条用例断的正是这份补丁要保住的行为。
