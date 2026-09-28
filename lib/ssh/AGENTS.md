# lib/ssh/AGENTS.md

本目录是会话层：`SessionManager`、`TerminalSession`、传输层、终端视图、凭据弹窗、连接入口、转发与跳板机。

根 `AGENTS.md` 的全局约定（平台兼容、状态与重建、字体、导入导出、文案、颜色、凭据、l10n）继续适用，这里只写本目录特有的东西——尤其是终端交互那一片：几乎每一条都是踩过的坑，且「直觉写法」往往是错的。

## 文件职责与踩坑

- `credential_store.dart` — 凭据安全存储抽象；`credential_store_io.dart` / `credential_store_stub.dart` 为条件导出的原生实现与 web 桩（同 local_write 模式）。`write` 返回是否真的落盘：底层故障不打断连接，但调用方必须提示「没存上」，绝不静默——钥匙串不可用时静默失败曾让「记住凭据」形同虚设
- `credentials_dialog.dart` — 连接前的凭据弹窗（密码 / 私钥 / agent 三选一，`lockRemember` 模式被「更换记住的凭据」复用），桌面与移动端共用；私钥可从文件选择或直接粘贴。Android 上文件选择必须带 `keyFileTypeGroups` 给的宽松 MIME 组（`*/*` + `application/octet-stream` + `text/plain`）：小米 / 澎湃（HyperOS）的「安全访问」选择器按 MIME 分类展示，而没有扩展名的 `id_rsa` / `id_ed25519` 正是 `application/octet-stream`，不声明就被藏起来、点不中。三项一起给是因为 `file_selector` 的 Android 端**只在过滤条件 ≥2 项时才写 `EXTRA_MIME_TYPES`**（只给一项 `*/*` 会落回 `setType` 分支，澎湃照样不放开）；其余平台必须保持空过滤——macOS / iOS 只认 extensions / UTI，塞 mimeTypes 会被判成不支持的过滤条件直接抛错。选择失败弹说明框（`showInfoDialog`）而不是轻提示：用户需要读到「重命名加 `.txt` 再选 / 改用粘贴」这类替代做法，并写明只按次读取选中的文件、不申请整机存储权限
- `host_key_store.dart` — 主机公钥指纹存储与 TOFU 校验决策。**一台主机存一组指纹**（`HostKeyRecord` 只含指纹），判据就是指纹本身：dartssh2 的指纹只哈希密钥体、不含算法名，所以同一把密钥换算法名指纹不变，按「算法名 + 指纹」比对会把良性协商变化误判成中间人。读取失败走 `HostKeysUnavailable` 并**拒绝连接**（fail closed，绝不按「从未记录」放行后覆盖可信记录）；`HostKeyChangedException` / `HostKeyUnavailableException` 分别归类为 `TerminalErrorKind.hostKey` / `.hostKeyStore`，前者才提供「清除记录的指纹并重连」，且文案必须带上指纹供用户与服务器核对
- `forward.dart` — 转发的公共类型：双向通道 `DuplexChannel`、服务端监听 `RemoteForwardListener`、本地 SOCKS5 代理 `DynamicForwardProxy`，以及失败归类 `ForwardErrorKind` / `ForwardException`（与平台无关，web 也要能编译）
- `tunnel_gateway.dart` — 转发本机一侧的网关（监听 / 拨号），条件导出 `tunnel_gateway_io.dart`（真套接字）与 `tunnel_gateway_stub.dart`（web 抛 `UnsupportedError`）
- `port_forward_runtime.dart` — `PortForwardManager`：把规则绑到某条会话的连接上，负责启停、状态与失败归类；生命周期与会话同生共死
- `jump_host.dart` — 跳板链路：`resolveJumpChain`（由外到内、环 / 缺主机 / 层数上限）、`connectionChain`、表单候选过滤 `jumpHostCandidates`、按跳包装错误的 `SshHopException` 与 `unwrapHopError`
- `ssh_agent.dart` — 本机 SSH agent 客户端：协议编解码（列密钥 / 签名，含 RSA 自动换 `rsa-sha2-256`）、一问一答的请求配对与 dartssh2 身份映射（`shouldProbe` 先探后签）；条件导出 `ssh_agent_io.dart`（macOS / Linux 走 `SSH_AUTH_SOCK`）与 `ssh_agent_stub.dart`（web）。Windows 的命名管道 agent 第一版不做（dart:io 连不上），`sshAgentSupported` 对其返回 false，UI 不给入口
- `connect_flow.dart` 的**无感 agent**：没有存档凭据时连接入口先问 `SessionManager.agentKeysProbe`（纯本地检查），本机 agent 有钥匙就经 `tryAgentConnect` 静默连一次——服务器认就免弹窗直连（会话照常留在管理器里）；钥匙被拒 / 连接中断才收掉探测会话、回常规凭据框，网络 / 主机密钥类失败保留错误现场不弹框。跳板链路同理：`SessionManager.hopAgentProbe` 逐跳静默试 agent（裸传输，不建会话）。两个探针都可注入，widget 测试必须注入假探针——默认实现会碰开发机真实的 `SSH_AUTH_SOCK`，结果随环境漂移
- `sftp.dart` / `dartssh2_sftp.dart` — SFTP 领域模型、抽象接口与 dartssh2 适配器
- `session_log.dart` — 会话日志是**终端缓冲区（含回滚）的纯文本快照**（`SessionLog.text` 取自 `Buffer.getText()`），不是另存一份远端原始字节流：原始流里混着 OSC 标题 / 配色 / bracketed paste，直接落盘就是满屏 `]0;host:~`、`[?2004h` 的 ESC 乱码，`\r` 重画与行编辑还会留下中间态。快照与画面同源，「画面上没有的日志里也没有」——输密码时远端关回显，密码因此进不了日志；代价是 `clear`、全屏程序退场后抹掉的内容不保留（同 iTerm2「保存内容」/ tmux capture-pane），长度上限是 `TerminalSession.terminal` 的 `maxLines`（把「日志」当成历史转录来改回去就是重犯这个 bug）
- `terminal_input_modifiers.dart` — 软键盘快捷键条的**粘滞修饰键**（`TerminalInputModifiers` + 纯函数 `applyTerminalModifiers`）：点亮即待命，下一个输入带上它、随后自动落回。触屏上不存在「按住 Ctrl 再按字母」（键条与软键盘不是同一块玻璃），照搬桌面的按住式修饰键等于没有。消费点在 `TerminalSession` 的 `_SessionTerminal`（`Terminal` 子类，覆盖 `keyInput` / `charInput` / `textInput` / `paste`）：软键盘敲下的字符不经过任何键位回调（xterm 的 `_onInsert` 先试 `keyInput`、认不出就直接 `textInput`），而包一层 `onOutput` 会被传输层在 `attach` 时整体覆盖，覆盖这四个公开方法才是最短的正路。粘贴永远不套修饰键
- `terminal_key_bar.dart` — 移动端软键盘上方的快捷键条（Esc / Tab / Ctrl / Alt / 方向键，可折叠、窄屏横向滚动）。**只在触屏平台挂载**（判 `defaultTargetPlatform` 而不是窗口宽度：窄窗口的桌面用户有物理键盘，给他塞一条软键盘键条只是噪声）。整条键条走 `GestureDetector` 而不是按钮——按钮参与焦点体系，点一下就把焦点从终端抢走、软键盘跟着收起；按键后由 `SshTerminalView._restoreTerminalFocus` 在**真的丢了焦点时**补回来（用户自己收键盘时焦点仍在终端上，无条件补焦点等于把键盘又弹回来）。待命提示浮在键条上方而不占布局：键条高度一变，PTY 就跟着重排一次。方向键右侧是 A- / A+ 两颗字号键（改的是 `TerminalStyleScope` 那一个全局字号，与设置页步进、Cmd/Ctrl 加减同源，边界置灰）
- 双指捏合缩放（触屏）：跨度用原始指针自己算（`_pinchPointers`，`Listener` 不进竞技场），**手势期间只出预览、抬手才写偏好**——字号一变 PTY 就要重排，逐帧改等于每帧给远端发一次 SIGWINCH。两个配套要点：一是手感，`_withGesturePhysics`（鼠标模式与捏合共用）把滚动物理换成 `NeverScrollableScrollPhysics`，否则两指张开时画面会跟着往下滚（物理一换，Scrollable 就算认领了拖动也走不动，连带把在飞的那次拖动一并作废）；二是让路，第二指落下时要把长按计时器、待开的链接、转发中的鼠标拖动、拖着的选区手柄一起收掉，它们不能跟捏合抢同一串指针。此前判断「捏合做不了」的依据（第一根手指被 Scrollable 认领后拿不到两指跨度）已被这条物理替换绕开
- 软键盘弹起 / 收起不能带着终端一起重排：键盘动画是**逐帧**的（Android 上一帧一个高度），而终端每变一行就重排行列、给远端发一次 window-change（SIGWINCH）——逐帧转发就是远端 shell / vim / tmux 重画十几遍，用户看到的正是「切到终端 Tab、键盘弹起」时画面抖。做法是**动画期间把终端渲染盒按在动画前的槽高上**（`_keyboardHold` + build 里的 `LayoutBuilder` / `OverflowBox`：底边仍贴槽位、多出来的上半截裁掉，所以提示符与光标不挪窝），键盘高度停稳 150ms 后才落定，整段动画只发一次。三个必须记住的点：一是**保持的目标是槽高而不是键盘高度**——home indicator / 导航条那一截 padding 会在键盘弹起时同时塌掉（`removePadding` 把它算进 padding），按键盘高度补差会多补一截；二是**键盘高度只能直接问 `FlutterView`**（`view.viewInsets.bottom / devicePixelRatio`），`resizeToAvoidBottomInset` 打开时 Scaffold 把 body 那层的 viewInsets 摘成了 0，而那层 MediaQuery 其余字段在动画期间一个都不变、body 子树连重建都不会发生，所以「读键盘、记槽高、排落定计时」都收在那一个只在布局期调用的方法里（`LayoutBuilder` 是唯一能逐帧进来的钩子）；三是**非键盘的布局变化立刻生效**（折叠键条、展开查找栏、拖窗口都不动键盘高度，差值恒为 0）。测试见 `test/terminal_ime_test.dart` 的「软键盘弹起不带着终端一起重排」组
- `terminal_mouse.dart` + 鼠标模式（触屏）：远端程序自己开了鼠标上报时（vim 的 `set mouse=a`、tmux 的 `mouse on`，判据是 `terminal.mouseMode != MouseMode.none`），键条上那颗「鼠标」键亮起；打开后拖动转发成远端的鼠标拖动，而不是滚本地画面（`ScrollConfiguration` 换 `NeverScrollableScrollPhysics`）。**生效条件是「开关打开 **且** 远端确实在收鼠标事件」**（`_mouseModeActive`）：只看开关的话，用户在普通 shell 里打开它就既不滚画面也发不出事件，等于把终端锁死；远端中途不再上报时还要替用户把开关关掉（否则那颗键会因「远端不上报」而置灰，用户连关都关不掉）。同时 `_setTrackpad` 会 `setSuspendPointerInput(true)` 停掉包内那层 tap 转发——不停的话一次轻点会发两遍按下 / 抬起（远端当成双击，tmux 会选词）。**移动事件得自己编**：`Terminal.mouseInput` 的 buttonState 只有 up / down，包里也没有任何地方读 `PointerInput.move`（那个枚举值是死的），而「按住左键拖」正是鼠标模式的全部意义。按下 / 抬起仍走 `mouseInput`，只有移动用 `encodeMouseEvent`，两边字节必须逐字一致（`test/terminal_key_bar_test.dart` 里有一条用例直接断言「拖动的第一笔 == 点击的第一笔」）。普通模式的坐标照抄包内 `MouseReporter`（含它行号多加 1 的老问题）：宁可一起偏，也不能让同一次拖动的按下与移动落在不同行上。发送走 `session.sendText` 绕过粘滞修饰键——那是原始转义序列，不该被 Ctrl 改写
- 选区手柄（触屏）：起点挂在首格左下角、终点挂在末格右下角，**只负责显示**。拖动判定收在 `_onPointerDown` / `_onPointerMove` 那串指针回调里（`_grabbedHandle` 自己算命中），不在浮层上挂手势识别器——浮层在 `Stack` 里的命中测试会被终端自己那层 `MouseRegion` 先接走，还会往竞技场里再塞一个平移识别器跟滚动抢。拖动时先把越界量换成滚动（一次最多三行），再把手指位置换算成格子，选区才落得跟手指一致；每次 `setSelection` 都要**新建两个锚点**——它会 dispose 掉上一对，复用同一个锚点第二次就被释放了。手柄几何靠 `_overlayRevision` 失效重算（选区变化 / 滚动 / 远端输出），只重建手柄那一小层
- 回滚搜索（`findTerminalMatches`，在 `terminal_interactions.dart`）：按行扫整块缓冲区，大小写不敏感、允许重叠命中、不跨行（终端里一行就是一条记录）。行文本与「字符串下标 → 格列」的映射由 `BufferLineText` 统一构建（与链接识别共用）：宽字符占两格，下标不能直接当格列用。**高亮底色必须半透明**——xterm 画高亮就是在字上面盖一个实心矩形（`paintHighlight` 只有 `drawRect`，主题里的 `searchHitForeground` 在包里根本没人读），不透明就把命中的字整片盖住。查找栏挂在终端与键条之间的 `Column` 里（不是浮层）：不遮输出，终端行数跟着它让出的高度重排；栏上的按钮走 `GestureDetector` 不碰焦点体系，否则点一下「下一个」软键盘就收起。每次输入都重扫一遍（50000 行满缓冲是最坏情况，感到卡再加去抖）。**命中行号是绝对行号，会过期**：远端 `clear`、reflow 合并行、切会话都会让先前的行号指到别处，所以输出时按 300ms 节流重算（保持当前那一条、不滚动），步进前再重算一次，画高亮时还要兜住越界（`buffer.createAnchor` 直接索引 `lines[y]`，不兜就是 RangeError）
- `terminal_view.dart` 的链接点击：**必须自己收原始指针事件**（`Listener` + `GlobalKey<TerminalViewState>` 取 `renderTerminal.getCellOffset`），不要用 `TerminalView.onTapUp`——xterm 4.0.0 里那条回调是断的（手势层 `_handleTapUp` 调的是 `onSingleTapUp`，而 `TerminalView` 把处理器传在 `onTapUp` 上，该字段在包内没有任何读取点，一次都不会触发；上游 master 同样如此，pub 上也没有更新的版本）。`Listener` 不参与手势竞技场，因此不会被包内层的 TapGestureRecognizer 挤掉；上游日后若修好，也**不要**把 onTapUp 一并接上——一次点击会开两个标签页。测试见 `test/terminal_convenience_test.dart` 的「链接点击」组（注入 `SshTerminalView.openLink` 假实现，别让测试去碰真实浏览器）
- 触屏那条路与鼠标**刻意不同**：鼠标单击链接要求按住 Cmd/Ctrl（防误触），触屏按不出修饰键，单击就打开——但要压一个 260ms 的双击窗口再开，否则 xterm 的双击选词在链接上永远选不中一个词（与侧边栏「双击直连」同一取舍）；全屏程序（`terminal.isUsingAltBuffer`，vim / less / tmux）里点按属于远端应用的鼠标上报，不抢来开浏览器。长按 550ms 弹会话菜单（复制 / 粘贴 / 全选，按在链接上多一项「打开链接」）：压后于 xterm 自己的 500ms 选词，菜单弹出时选区已落定，同样在 `Listener` 里自己计时，不去手势竞技场里抢。测试见 `test/terminal_key_bar_test.dart`
- 终端的滚动控制器由 `SshTerminalView` 自己持有（`_scrollController`，连同 `focusNode` 一起交给 `TerminalView`，谁创建谁 dispose）：喂给 xterm 的 Scrollable、滚动条与「回到最新」按钮同一个位置。xterm 只在**用户输入**时跳到底，远端输出不会把画面拽走，所以滚上去之后需要这颗按钮（`jumpTo(maxScrollExtent)`，不用 `animateTo`——远端还在输出时目标值每帧都过期）。滚动条只挂触屏平台：桌面端 `MaterialScrollBehavior` 自己会加一条，再加就是两条；`interactive` 保持 false，拖拇指要跟包内层的选字识别器抢竞技场，更深的那一个（xterm）会赢
- 链接的悬停提示：**按住 Cmd/Ctrl 悬停才出现**（下划线 + 手型光标），与点击同一条判定——修饰键状态是判定结果的一部分，松手必须立刻收回。判定结果 `TerminalLink`（`findLinkAtCell` 返回 URL + 格子跨度）走一个 `ValueNotifier`，同时喂 `TerminalView.mouseCursor` 与浮层 `LinkUnderlinePainter`（`IgnorePointer`，不接指针事件）。下划线几何必须问 `RenderTerminal.getOffset` 再用 `globalToLocal` 换算：浮层与终端之间隔着 Container 的 padding，自己乘格宽会和包对不上。滚动（`ScrollNotification`）与远端输出（`terminal.addListener`）都要重算，否则指针不动、画面滚了之后会留下一条错位的线；拖动选字期间不显示
- `session_page.dart` — 移动端全屏终端页。**刻意不挂 AppBar**：手机上 AppBar + 状态栏要吃掉约 80pt，软键盘弹起时终端只剩个位数行。改成浮在终端之上的一条头部（返回 / 主机名 / 状态胶囊 / 断开）：进页面亮 3 秒自动收起，轻点顶部一条唤出，点终端正文立刻收回。两条实现要点——唤出条是 `HitTestBehavior.translucent` 的 `Listener`，只把自己加进命中结果、不吃掉事件，终端照样收得到那一下轻点，`Listener` 也不进手势竞技场；收起后整条头部包在 `IgnorePointer` 里，否则透明的一层仍然会拦住终端的点击。底色跟着终端配色（不挂 AppBar 后状态栏那一带露的是 Scaffold 底色，与终端底色差一点就是一道接缝）
- `session_menu.dart` / `session_log_dialog.dart` — 会话菜单（一行一条会话：状态点 + 远端 OSC 标题 + 行尾关闭，另有「新建会话」与「会话日志」）与日志弹窗。点状态胶囊的规则收在 `openSessionPill` 一处：**只有一条会话时直接进日志**（多会话功能之前就是这个行为，界面不许变），多开了才换成菜单。桌面详情头部、移动端主机详情页、移动端全屏终端页共用它——移动端此前只接了日志，「同一台主机再开一条」在手机上因此没有入口
- `sftp_browser.dart` / `sftp_transfer.dart` — SFTP 面板状态：目录浏览与串行传输队列（UI 入口在 `lib/widgets/sftp_browser.dart`，见 `lib/widgets/AGENTS.md`）
- `local_files.dart` — 本地文件网关（选文件 / 落盘 / 导出落点）；`local_write*.dart` 为按平台条件导出的落盘实现（含 `promote` 改名与 `ownerOnly` 权限收紧），`local_chmod.dart` 是只为 0600 存在的最小 FFI 绑定，`local_share*.dart` 为按平台条件导出的分享面板实现

## 终端输入（xterm fork）

- 终端输入：中文这类输入法**上屏的那条路在上游 xterm 里是坏的**，靠仓库内的 `third_party/xterm` 修（`dependency_overrides` 挂的，不是 pub 上的包；机制、补丁内容与升级做法见 `third_party/README.md`）。两条规矩：一是 `TerminalView.deleteDetection` **只在触屏平台开**——桌面端的退格是真实按键事件，开了就把平台编辑状态挂到那个两空格占位符上、走的正是上游没修的那条差集分支；二是 `test/terminal_ime_test.dart` 断的就是这份补丁的行为（一笔提交被引擎重发三遍只上屏一次、同一个字连打两次仍发两遍、重新聚焦后第一笔输入不被镜像吞掉），动 fork 之前先让它绿

## SFTP 层

- SFTP 通道复用会话已认证的 SSH 连接（`SshTransport.openSftp`），不另建 TCP、不重复认证
- 失败 / 取消只清临时文件，绝不删目标；但进程被强杀时可能留下 `<文件>.noshell-part`（远端那份用户看不见，要手动清）
- `lib/` 内禁止直接 `import 'dart:io'`；本地文件能力一律走 `ssh/local_write.dart` 的条件导出，web 由桩实现兜底（这条是全局铁律，根 `AGENTS.md` 也列了一份）
- 传输进度只通知 `SftpTransfer` 自身，面板按行订阅；队列结构变化才通知整块面板
- 删除主机时凭据与指纹一并清理，且**不 await**：钥匙串 / 存储层卡住不能把删除本身拖住（只影响下次连接的判定）。代价是「撤销删除」恢复的主机没有指纹，下次连接按首次记录处理——这是刻意取的舍
- 上传 / 下载一律**先写临时文件、成功后再改名到目标**（远端与本地同名，都是 `.noshell-part`；本地后缀与远端一致，残留才看得出是谁留下的）：直接往目标上写（远端是 `truncate`）一旦中途失败或取消，用户原有的同名文件就没了；失败与取消只清临时文件，绝不删目标
- `SftpTransferQueue.dispose()` 只清自己的记录，不打断在跑的传输：`_drain` 与下载循环在 `await` 之后都必须复查 `_disposed` 再改状态或通知，否则会对已 dispose 的 `SftpTransfer` 调 `notifyListeners()`（debug 下直接抛 `used after being disposed`）
- `_mutate` 的 `isMutating` 必须保持到**刷新结束**才放开：刷新在大目录 / 慢链路上要几百毫秒，提前放开等于允许第二个结构性操作挤进刷新窗口；忙时抛 `SftpErrorKind.busy`，不静默 return（那会让调用方谎报成功）
- 下载落点数量必须与目标一一对应才开工：网关换了实现（移动端 SAF 选择器）可能少回落点，直接下标取用会在循环中途 RangeError，而前面的任务已经入队
- 文件行的「进入 / 选中」只让**鼠标**在按下那一刻生效（`Listener.onPointerDown` 先过 `_isPointerInstant`；桌面端单击要「点哪选哪」，等不起双击手势在竞技场里的超时）；手指与笔的按下不算数——按下即生效的话，从某一行起手的那次滑动会在手指还没抬起时就进入那个目录（用户想滚列表，人已经在文件夹里了）。宽屏触屏设备（平板 / 折叠屏 / 分屏窗口）的 `compact` 为 false，靠的就是这条指针判据。触屏（compact）的单击走 `GestureDetector.onTap`，与 ListView 的拖动同场竞技：移动超过 slop 就是拖动胜出、这次点击随之作废（不要去自己量位移，竞技场本来就是干这个的）；compact 也不挂 `onDoubleTap`——它会把单击扣住 300ms 等第二下，而重复进入由 `SftpBrowserController.navigate` 的 `_loadingTarget` 判重兜住
- 触屏的目录行行尾给一个 `chevron_right`：同一行上「点目录进下一层 / 点文件是多选」得让人一眼分得出来，没有悬停提示的触屏只能靠它

## 端口转发

- 规则是**静态配置**，存在 `SshServer.forwards` 里随主机一起落盘；启停状态属于运行时，挂在主机的活跃会话上（`TerminalSession.forwards`）。没有会话时列表照常展示，但开关禁用并提示先连接
- 通道复用会话已认证的连接（与 SFTP 同样的取舍）：不另建 TCP、不重复认证，会话断开即随之失效；三种模式的差异只在「哪一头监听」——`-L` 本机监听 + 每个连接开一条直连通道，`-R` 请服务端监听 + 每个入站连接拨到本机，`-D` 交给 dartssh2 的本地 SOCKS5（web 没有原始 TCP，整条路径在 `tunnel_gateway_stub` 处兜底为不支持）
- `PortForwardRule.isRunnable` 按模式分别判定：动态转发不看远端地址，远程转发的远端端口 0 是「让服务端分配」而不是没填
- 关掉监听时**不等** `subscription.cancel()` 完成：不再收新连接在调用返回时已生效，等它只会把「用户点了停止」拖在事件循环上
- 编辑主机时（表单在 `lib/widgets/host_form.dart`，桌面弹窗与移动端编辑页共用）构造 `SshServer` 是**从零拼**（不是 copyWith），必须显式带上 `forwards`，漏掉就是每编辑一次静默清空该主机的全部转发规则；跳板机同理，直接传 `jumpServerId`（null 即清除），别再拼一次 `copyWith(clearJumpServer:)`

## 跳板机

- 存的是**跳板机的 id**（`SshServer.jumpServerId`），不是地址副本：跳板机自己也有端口、用户名与凭据，复制一份必然走样；链路在连接时解析（`resolveJumpChain`），环 / 跳板机被删 / 层数超限都在这里挡下并给出可操作的提示
- 一跳一份凭据：连接流程逐跳取凭据（存过就用，没存过当场弹窗），任意一跳取消即整条连接取消；失败按跳包装成 `SshHopException`，归类与文案用 `unwrapHopError` 剥出真原因，界面必须指明是**哪一跳**出的问题
- 主机指纹校验逐跳进行：跳板机指纹不一致时，`hostKeyChanged` 带的是那一跳的地址，「清除指纹并重连」清的也必须是那一跳的记录
