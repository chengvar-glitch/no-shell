# AGENTS.md

## 项目概述

`no_shell`（编译产物 `NoShell`）是一个 Flutter 应用（SSH 连接管理器），需同时兼容六个平台。桌面宽屏（≥640px）为左右分栏布局，窄屏切换为移动端底部导航骨架，两端复用同一套数据层与会话层。主机列表与分组布局、偏好（主题 / 语言 / 终端配色·字体·字号）经 shared_preferences 持久化（见 `server_persistence.dart`、`settings_persistence.dart`；主机列表出厂为空，不预置任何示例数据）；界面字体固定跟随系统、不提供自定义，终端字体只用随包内置的两个族（JetBrains Mono / Fira Code）与「系统等宽」（见 `assets/fonts/`）。用户勾选「记住凭据」时，凭据经 flutter_secure_storage 加密落盘（web 端不支持，弹窗自动隐藏该选项），未记住的凭据仅存内存。SSH 连接由 dartssh2 驱动，终端由 xterm 渲染，界面文案全部中英双语。远程仓库 `origin` 为 `github.com/chengvar-glitch/no-shell`（私有），默认分支 `main`。

## 常用命令

- 安装依赖：`flutter pub get`
- 静态分析：`flutter analyze`（提交前必须无告警）
- 运行全部测试：`flutter test`
- 运行单个测试文件：`flutter test test/xxx_test.dart`
- 运行应用：`flutter run -d macos`（或 `-d chrome` / `-d <device-id>`，用 `flutter devices` 查看可用设备）
- 格式化：`dart format <文件>`（新改动的文件必须格式化）
- 生成本地化代码：`flutter gen-l10n`（修改 arb 后执行）
- SSH 链路冒烟：`dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码>`（或 `--identity <PEM路径>`，或 `--agent` 走本机 SSH agent 的密钥认证，密钥需先 `ssh-add` 装入 `SSH_AUTH_SOCK` 指向的 agent），追加 `--shell` 验证 PTY、`--sftp` 验证 SFTP 浏览与上传下载链路；凭据只经命令行传入
- 转发 / 跳板机冒烟：`NOSHELL_SMOKE_HOST=<host> NOSHELL_SMOKE_PASSWORD=<密码> flutter test test/forward_smoke_test.dart`（可选 `NOSHELL_SMOKE_USER` / `NOSHELL_SMOKE_PORT`）。它必须跑 App 自己的会话层（models 依赖 Flutter），所以只能在测试 VM 里跑而不是 `dart run`；没给环境变量时整组自动跳过，`flutter test` 照常全绿
- Agent 认证冒烟：`SSH_AUTH_SOCK=<agent套接字> NOSHELL_SMOKE_HOST=<host> flutter test test/agent_smoke_test.dart`（可选 `NOSHELL_SMOKE_USER` / `NOSHELL_SMOKE_PORT`；不传密码，认证完全交给 agent 里的密钥）。与转发冒烟同样的跳过约定
- macOS 本机稳定签名（一次性）：`./tool/setup_dev_codesign.sh`——生成自签代码签名证书并设为信任锚（需输一次登录密码），写入 gitignore 的 `macos/Runner/Configs/local.xcconfig`。动机与机制见编辑约定的「macOS 签名」条

## 环境与依赖约束

- Dart SDK：`^3.13.3`（见 `pubspec.yaml`）
- Lint 规则：`flutter_lints ^6.0.0`，通过 `analysis_options.yaml` 引入 `package:flutter_lints/flutter.yaml`
- 运行时依赖：`dartssh2 ^4.1.0`（SSH 传输 / SFTP）、`xterm ^4.0.0`（终端渲染）、`url_launcher ^6.3.2`（终端里的链接与发布页交给系统浏览器打开）、`file_selector ^1.1.0`（上传选文件、下载另存为）、`share_plus ^13.3.0`（移动端导出的系统分享面板）、`path_provider ^2.1.6`（下载默认目录 / 导出临时目录）、`pointycastle ^4.0.0`（加密备份的 scrypt + AES-256-GCM，纯 Dart、六端通用）、`ffi ^2.1.0`（只用于绑 libc 的 chmod，导出备份收到 0600）、`flutter_secure_storage`（凭据安全存储，macOS 需钥匙串 entitlement，已在 entitlements 中配置）、`shared_preferences`（主机列表持久化）、`package_info_plus ^10.2.1`（读宿主包信息拿真实版本号，见 `app_version.dart`）、`flutter_localizations` + `intl`（国际化）
- 添加新依赖必须同步更新 `pubspec.yaml` 并重新执行 `flutter pub get`

## 目录结构

- `lib/main.dart` — 应用入口（`NoShellApp`），持有全局状态并按窗口宽度切换桌面/移动骨架
- `lib/host_portable.dart` — 主机文本格式编解码（中英文 key 识别，也用于新建表单的元数据粘贴）；`lib/host_backup.dart` 为备份文件的信封编解码（scrypt 派生密钥 + AES-256-GCM，明文即上面的主机文本，`.nsbak` 后缀）；`lib/host_transfer.dart` 为导入 / 导出用户流程，落盘与合并逻辑只此一份，文件交互经 `LocalFileGateway`
- `lib/models.dart` — `SshServer` 等数据模型与示例数据（含 JSON 序列化）；`ServerGroup` 是渲染用的分组视图（名字 + 成员 + 折叠态）
- `lib/server_persistence.dart` — 主机列表与分组布局落盘通道（`ServerArchive` 快照 + `ServerPersistence` 抽象 + shared_preferences 实现）；主机条目与分组布局各存一个 key。`load()` 返回 `ServerArchiveLoad` 三态（`Missing` / `Loaded` / `Unreadable`）而不是可空存档：「没有存档」与「存档读不出来」必须分开，否则后者会被当成首次运行、随即被空列表覆盖掉。只读当前格式，不做旧档迁移
- `lib/settings_persistence.dart` — 偏好落盘通道（`AppSettings` 快照：主题 / 语言 / 终端配色·字体·字号；`SettingsPersistence` 抽象 + shared_preferences 实现，枚举按名字存取）。单个字段认不出来只退回该字段默认值，不让一条脏数据带走整份偏好；不认得的字段读时忽略、下次保存即被抹掉——开发阶段不做版本号也不做旧字段迁移
- `lib/store.dart` — `ServerStore`（主机列表 + 分组注册表，ChangeNotifier，可选持久化）。分组以「名字」为身份（`SshServer.group` 存的就是分组名），注册表负责顺序、空分组与折叠态，提供 `createGroup` / `renameGroup` / `deleteGroup` / `moveGroup` / `setGroupCollapsed`；落盘串行排队，避免连续变更时旧快照最后落盘。存档不可读时置 `archiveUnreadable` 并**停写**（`_schedulePersist` 直接返回）：此时内存列表是残缺的，落盘等于抹掉用户仅存的数据；该状态由设置页顶部的 `ArchiveWarningCard` 告知用户
- `lib/theme.dart` — `AppPalette` 色板、`AppTheme` 主题构建（按亮度缓存；界面字体固定跟随系统，`ThemeData` 不再按字体分叉）、`AppThemeX` 语义色扩展
- `lib/settings.dart` — 偏好模型：`TerminalFont`（终端字体目录：族名 / 缺字形回退链 / 名称）、`TerminalPreset`（配色）、`TerminalStylePrefs`（配色 + 字体 + 字号）与 `TerminalStyleScope`；`kBundledFontLicenses` 登记内置字体的 OFL 文本 asset
- `lib/app_version.dart` + `lib/update_check*.dart` — 软件版本检测。`app_version.dart` 的 `appVersion` 是**可变全局**（启动时由 `loadAppVersion()` 从 `package_info_plus` 写入，读不到才退回常量 `kFallbackAppVersion`），因为「关于」与设置页都在同步的 `build` 里取它。`update_check_client.dart` 是纯 Dart 的模型与版本比较（六端通用），`update_check_io.dart` / `_stub.dart` 是 `dart:io` 的 `HttpClient` 实现与 web 桩，`update_check_state.dart` 是唯一状态源 `UpdateCheckService`，`update_launcher*.dart` 负责把发布页交给系统浏览器。UI 共用件是 `widgets/settings_controls.dart` 里的 `UpdateSettingsRow` 与 `UpdateAvailableDot`
- `lib/home_page.dart` — 桌面端左右分栏骨架（侧边栏固定宽度、可整体收起，不提供拖拽调宽）。主机行交互：单击选中、**双击直连**（选中 + 发起连接 + 详情面板落到终端 Tab；已连接时双击只跳转不断开——双击是「给我终端」，不是连接开关）。详情面板当前 Tab 下标归 `ShellLayoutState.detailTab`（外部入口改写它、用户点 Tab 写回它），双击检测在 tile 里自己量点击间隔，**不许**把 `onDoubleTap` 挂上同一块 InkWell——框架的双击手势会把单击在竞技场里扣住 300ms 才放行，单击选中跟着迟钝（与 `terminal_view.dart` 链接点击自收指针事件是同一类取舍）
- `lib/widgets/` — 桌面端组件（侧边栏、详情面板、SFTP 面板、状态徽章）；`port_forward_panel.dart` 为「转发」页（规则列表 + 新建 / 编辑弹窗），桌面与移动端共用；`jump_host_field.dart` 为跳板机下拉（桌面弹窗与移动端编辑页共用）；`sftp_browser.dart` 为库入口，组件按区域拆在同目录的 `sftp_browser_*.dart` part 文件中，外部只可见 `SftpTab`；`settings_controls.dart` 为设置面板共用件（分组卡片 `SettingsSection` / `SettingsCard` / 设置行 `SettingsRow` / `SettingsIconButton`、各设置控件，以及四个分区的正文 `AppearanceSettingsSection` / `TerminalSettingsSection` / `LanguageSettingsSection` / `ConnectionSettingsSection`，外加「更新」分区的 `UpdateSettingsRow` 与红点 `UpdateAvailableDot`），桌面设置弹窗与移动端设置 Tab 共用同一套，两端观感必须一致，只差配色选择器的形态（宽屏色卡平铺 / 窄屏下拉）；`host_form.dart` 为主机表单共用件（`HostFormController` 持有输入框、校验与保存时构造 `SshServer`，`HostFormFields` 是字段列，`AuthMethodSelector` 是认证方式三段选择器），桌面编辑弹窗与移动端编辑页共用——两端外壳不同（弹窗 / 整页），字段、校验与主机构造只此一份；`group_controls.dart` 为分组共用件（分组下拉 `GroupField`——只选已建分组，新建分组走分组菜单；重命名 / 删除 / 移动分组流程 `runGroupAction`；六项菜单的条目表 `groupMenuItems`），桌面侧边栏与移动端主机页共用，两端观感必须一致；`session_selection.dart` 为详情视图「当前会话 + 会话条数」的无变化守卫 mixin `SessionSelectionGuard`（切会话只发会话层通知，store 那一路重建不起来），桌面详情面板与移动端详情页共用；`session_idle_view.dart` 为未连接 Tab 的引导空态共用件（图标 + 标题 + 提示 + 可选重连按钮），SFTP Tab 与移动端终端 Tab 共用保持同页空态观感一致，桌面端终端 Tab 仍走终端样式预览（两端刻意不同，见 `TerminalTab.idleStyle`）；`password_dialog.dart` 为备份口令弹窗（`BackupPasswordMode.create` 设口令并二次确认 / `.open` 输一次口令）；`confirm_dialog.dart` 为确认框 / 说明框 / 轻提示共用件（`showConfirmDialog` 危险确认统一红色实心按钮 / `showInfoDialog` 单键说明框，给「用户得读完才能做对」的失败指引用 / `showToast` 统一轻提示），删除主机、删分组、删转发、删文件等确认一律走它，不要各处自绘；`about_dialog.dart` 为「关于」入口（`showAppAboutDialog`，观感与 `showAboutDialog` 一致，只多一层 macOS 适配——许可页自带 AppBar，返回键默认落在红绿灯底下，靠给对话框那层塞让位主题、再被 `showLicensePage` 的 `InheritedTheme.capture` 带进许可页来挪开）
- `lib/ssh/` — 会话层（`SessionManager`、`TerminalSession`、传输层、终端视图、凭据弹窗、连接入口）
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
  - `terminal_key_bar.dart` — 移动端软键盘上方的快捷键条（Esc / Tab / Ctrl / Alt / 方向键，可折叠、窄屏横向滚动）。**只在触屏平台挂载**（判 `defaultTargetPlatform` 而不是窗口宽度：窄窗口的桌面用户有物理键盘，给他塞一条软键盘键条只是噪声）。整条键条走 `GestureDetector` 而不是按钮——按钮参与焦点体系，点一下就把焦点从终端抢走、软键盘跟着收起；按键后由 `SshTerminalView._restoreTerminalFocus` 在**真的丢了焦点时**补回来（用户自己收键盘时焦点仍在终端上，无条件补焦点等于把键盘又弹回来）。待命提示浮在键条上方而不占布局：键条高度一变，PTY 就跟着重排一次。方向键右侧是 A- / A+ 两颗字号键（改的是 `TerminalStyleScope` 那一个全局字号，与设置页步进、Cmd/Ctrl 加减同源，边界置灰）——**没有做双指捏合缩放**：xterm 的拖选是鼠标专用（`supportedDevices: {mouse}`），触屏上单指拖动归 Scrollable，第一根手指被它认领之后就拿不到完整的两指跨度了；何况逐帧改字号会让 PTY 每帧重排一次
  - `terminal_mouse.dart` + 鼠标模式（触屏）：远端程序自己开了鼠标上报时（vim 的 `set mouse=a`、tmux 的 `mouse on`，判据是 `terminal.mouseMode != MouseMode.none`），键条上那颗「鼠标」键亮起；打开后拖动转发成远端的鼠标拖动，而不是滚本地画面（`ScrollConfiguration` 换 `NeverScrollableScrollPhysics`）。**移动事件得自己编**：`Terminal.mouseInput` 的 buttonState 只有 up / down，包里也没有任何地方读 `PointerInput.move`（那个枚举值是死的），而「按住左键拖」正是鼠标模式的全部意义。按下 / 抬起仍走 `mouseInput`，只有移动用 `encodeMouseEvent`，两边字节必须逐字一致（`test/terminal_key_bar_test.dart` 里有一条用例直接断言「拖动的第一笔 == 点击的第一笔」）。普通模式的坐标照抄包内 `MouseReporter`（含它行号多加 1 的老问题）：宁可一起偏，也不能让同一次拖动的按下与移动落在不同行上。发送走 `session.sendText` 绕过粘滞修饰键——那是原始转义序列，不该被 Ctrl 改写
  - 选区手柄（触屏）：起点挂在首格左下角、终点挂在末格右下角，**只负责显示**。拖动判定收在 `_onPointerDown` / `_onPointerMove` 那串指针回调里（`_grabbedHandle` 自己算命中），不在浮层上挂手势识别器——浮层在 `Stack` 里的命中测试会被终端自己那层 `MouseRegion` 先接走，还会往竞技场里再塞一个平移识别器跟滚动抢。拖动时先把越界量换成滚动（一次最多三行），再把手指位置换算成格子，选区才落得跟手指一致；每次 `setSelection` 都要**新建两个锚点**——它会 dispose 掉上一对，复用同一个锚点第二次就被释放了。手柄几何靠 `_overlayRevision` 失效重算（选区变化 / 滚动 / 远端输出），只重建手柄那一小层
  - 回滚搜索（`findTerminalMatches`，在 `terminal_interactions.dart`）：按行扫整块缓冲区，大小写不敏感、允许重叠命中、不跨行（终端里一行就是一条记录）。行文本与「字符串下标 → 格列」的映射由 `BufferLineText` 统一构建（与链接识别共用）：宽字符占两格，下标不能直接当格列用。**高亮底色必须半透明**——xterm 画高亮就是在字上面盖一个实心矩形（`paintHighlight` 只有 `drawRect`，主题里的 `searchHitForeground` 在包里根本没人读），不透明就把命中的字整片盖住。查找栏挂在终端与键条之间的 `Column` 里（不是浮层）：不遮输出，终端行数跟着它让出的高度重排；栏上的按钮走 `GestureDetector` 不碰焦点体系，否则点一下「下一个」软键盘就收起。每次输入都重扫一遍（50000 行满缓冲是最坏情况，感到卡再加去抖）
  - `terminal_view.dart` 的链接点击：**必须自己收原始指针事件**（`Listener` + `GlobalKey<TerminalViewState>` 取 `renderTerminal.getCellOffset`），不要用 `TerminalView.onTapUp`——xterm 4.0.0 里那条回调是断的（手势层 `_handleTapUp` 调的是 `onSingleTapUp`，而 `TerminalView` 把处理器传在 `onTapUp` 上，该字段在包内没有任何读取点，一次都不会触发；上游 master 同样如此，pub 上也没有更新的版本）。`Listener` 不参与手势竞技场，因此不会被包内层的 TapGestureRecognizer 挤掉；上游日后若修好，也**不要**把 onTapUp 一并接上——一次点击会开两个标签页。测试见 `test/terminal_convenience_test.dart` 的「链接点击」组（注入 `SshTerminalView.openLink` 假实现，别让测试去碰真实浏览器）
  - 触屏那条路与鼠标**刻意不同**：鼠标单击链接要求按住 Cmd/Ctrl（防误触），触屏按不出修饰键，单击就打开——但要压一个 260ms 的双击窗口再开，否则 xterm 的双击选词在链接上永远选不中一个词（与侧边栏「双击直连」同一取舍）；全屏程序（`terminal.isUsingAltBuffer`，vim / less / tmux）里点按属于远端应用的鼠标上报，不抢来开浏览器。长按 550ms 弹会话菜单（复制 / 粘贴 / 全选，按在链接上多一项「打开链接」）：压后于 xterm 自己的 500ms 选词，菜单弹出时选区已落定，同样在 `Listener` 里自己计时，不去手势竞技场里抢。测试见 `test/terminal_key_bar_test.dart`
  - 终端的滚动控制器由 `SshTerminalView` 自己持有（`_scrollController`，连同 `focusNode` 一起交给 `TerminalView`，谁创建谁 dispose）：喂给 xterm 的 Scrollable、滚动条与「回到最新」按钮同一个位置。xterm 只在**用户输入**时跳到底，远端输出不会把画面拽走，所以滚上去之后需要这颗按钮（`jumpTo(maxScrollExtent)`，不用 `animateTo`——远端还在输出时目标值每帧都过期）。滚动条只挂触屏平台：桌面端 `MaterialScrollBehavior` 自己会加一条，再加就是两条；`interactive` 保持 false，拖拇指要跟包内层的选字识别器抢竞技场，更深的那一个（xterm）会赢
  - 链接的悬停提示：**按住 Cmd/Ctrl 悬停才出现**（下划线 + 手型光标），与点击同一条判定——修饰键状态是判定结果的一部分，松手必须立刻收回。判定结果 `TerminalLink`（`findLinkAtCell` 返回 URL + 格子跨度）走一个 `ValueNotifier`，同时喂 `TerminalView.mouseCursor` 与浮层 `LinkUnderlinePainter`（`IgnorePointer`，不接指针事件）。下划线几何必须问 `RenderTerminal.getOffset` 再用 `globalToLocal` 换算：浮层与终端之间隔着 Container 的 padding，自己乘格宽会和包对不上。滚动（`ScrollNotification`）与远端输出（`terminal.addListener`）都要重算，否则指针不动、画面滚了之后会留下一条错位的线；拖动选字期间不显示
  - `session_page.dart` — 移动端全屏终端页。**刻意不挂 AppBar**：手机上 AppBar + 状态栏要吃掉约 80pt，软键盘弹起时终端只剩个位数行。改成浮在终端之上的一条头部（返回 / 主机名 / 状态胶囊 / 断开）：进页面亮 3 秒自动收起，轻点顶部一条唤出，点终端正文立刻收回。两条实现要点——唤出条是 `HitTestBehavior.translucent` 的 `Listener`，只把自己加进命中结果、不吃掉事件，终端照样收得到那一下轻点，`Listener` 也不进手势竞技场；收起后整条头部包在 `IgnorePointer` 里，否则透明的一层仍然会拦住终端的点击。底色跟着终端配色（不挂 AppBar 后状态栏那一带露的是 Scaffold 底色，与终端底色差一点就是一道接缝）
  - `session_menu.dart` / `session_log_dialog.dart` — 会话菜单（一行一条会话：状态点 + 远端 OSC 标题 + 行尾关闭，另有「新建会话」与「会话日志」）与日志弹窗。点状态胶囊的规则收在 `openSessionPill` 一处：**只有一条会话时直接进日志**（多会话功能之前就是这个行为，界面不许变），多开了才换成菜单。桌面详情头部、移动端主机详情页、移动端全屏终端页共用它——移动端此前只接了日志，「同一台主机再开一条」在手机上因此没有入口
  - `sftp_browser.dart` / `sftp_transfer.dart` — SFTP 面板状态：目录浏览与串行传输队列
  - `local_files.dart` — 本地文件网关（选文件 / 落盘 / 导出落点）；`local_write*.dart` 为按平台条件导出的落盘实现（含 `promote` 改名与 `ownerOnly` 权限收紧），`local_chmod.dart` 是只为 0600 存在的最小 FFI 绑定，`local_share*.dart` 为按平台条件导出的分享面板实现
- `lib/mobile/` — 移动端四个 Tab 及详情/编辑页
- `lib/l10n/` — arb 源文件（`app_en.arb` / `app_zh.arb`）；`lib/l10n/generated/` 为生成代码
- `assets/fonts/` — 随包内置的终端字体（`jetbrains_mono/`、`fira_code/` 各含 Regular + Bold 与 `OFL.txt`，合计约 1.2 MB），由 `pubspec.yaml` 的 `fonts:` 声明、`assets:` 声明许可文本。族名一律带 `NoShell ` 前缀（如 `NoShell JetBrains Mono`）：与系统字体彻底解耦，引擎必定命中随包文件
- `test/` — widget、mobile、session_manager、localization、persistence（序列化与持久化）、groups（分组建模 / 排序 / 落盘迁移与两端交互）、credentials_dialog、connect_flow、host_key（TOFU 决策与处置入口）、host_transfer（主机文本格式解析）、host_backup（备份信封与导入 / 导出流程）、sftp（browser / adapter / tab 三组）、window_caption（自绘标题条）、font_assets（内置字体与 pubspec / 许可 / FontManifest 的接线校验）、port_forward（规则模型 + 三种模式的运行时）、port_forward_panel（转发页交互）、jump_host（链路解析 / 候选过滤 / 逐跳失败归类 / 连接流程弹窗）、ssh_agent（agent 协议 / 身份映射 / 会话归类）、update_check（版本比较 / GitHub 查询 / 状态与设置页交互）测试；`terminal_key_bar_test.dart` 覆盖移动端快捷键条、粘滞修饰键的输入变换与触屏长按 / 点链接；`forward_smoke_test.dart` / `agent_smoke_test.dart` 是需要真实主机的冒烟（无环境变量时自动跳过）；`test/support/` 放共享假实现（含 `FakeCredentialStore`、`forward_fakes.dart` 里的假通道 / 假网关 / 假转发传输）
- `integration_test/` — 驱动真实应用的集成测试：`screenshots_test.dart` 为 README 截图生成器（演示链路走本地一次性服务端，输出 `docs/screenshots/`），`mobile_connect_test.dart` 在模拟器 / 真机上跑移动端「连接 → 终端 → SFTP → 断开」全流程。两者都要真机或模拟器，不进 CI；缺前置时自动跳过
- `tool/` — 开发脚本（`install_local_linux.sh` 把 `build/linux/x64/release/bundle` 按 release.yml 的 deb 布局装到本机（`/opt/noshell` + `/usr/local/bin/noshell` + hicolor 图标 + 桌面入口，需 sudo）；`smoke_ssh.dart` 冒烟脚本，`dev_sftp_server.py` 是配套的一次性本地 SFTP + 假 shell 服务端，只绑 127.0.0.1、账号 smoke/smoke，供 `--sftp` / `--shell` 冒烟与截图使用；`setup_dev_codesign.sh` 为 macOS 本机开发证书签名的一次性配置脚本）
- `docs/screenshots/` — README 截图，由 `integration_test/screenshots_test.dart` 生成，禁止放入真实主机信息
- `docs/prototypes/` — 设计评审用的交互原型图（`mobile-terminal-ux.png`）与其渲染脚本 `render.py`（Pillow 直绘，无第三方依赖；`python3 docs/prototypes/render.py` 重跑）。只给人看布局，不参与构建、不进版本日志
- `icon/` — 应用图标：`art.svg` 是唯一样式来源，`render.py` 生成 `png/` 全套尺寸；iOS / macOS / Windows / Android / Web 由 `dart run flutter_launcher_icons`（配置在 `pubspec.yaml`）写入平台目录，Linux 走 `icon/png/linux/*.png`，由 `release.yml` 装成 hicolor 主题
- `android/` `ios/` `macos/` `linux/` `windows/` `web/` — 六个平台的原生宿主工程；`analysis_options.yaml` 已排除这些目录。macOS **未开 App Sandbox**：沙盒下钥匙串访问组必须通过 application-identifier（团队签名）校验，而项目无 Apple 团队（ad-hoc，TeamIdentifier=not set），$(AppIdentifierPrefix) 展开为空，flutter_secure_storage 读写一律 -34018；同时 macOS 侧 `MacOsOptions.usesDataProtectionKeychain` 必须为 false（数据保护钥匙串同样要求团队签名）。恢复沙盒的前提是接入 DEVELOPMENT_TEAM 并逐项重验凭据链路（本机开发的证书签名与钥匙串授权弹窗问题见编辑约定「macOS 签名」条）

## 编辑约定

- 所有应用代码放在 `lib/` 下；不要手改平台目录中的生成文件，除非是插件集成所需的配置（如权限声明）
- `lib/l10n/generated/` 下的文件为生成产物，禁止手改；文案改动一律修改 arb 源文件后执行 `flutter gen-l10n`
- 所有面向用户的文案必须经 `AppLocalizations` 获取，禁止硬编码字符串；新增文案需同时补齐 en/zh 两个 arb
- 平台兼容：代码需同时兼容全部六个平台；web 无原生 TCP，SSH 连接会抛 `UnsupportedError`，依赖 `TerminalErrorKind.unsupported` 归类处理，不得移除该路径
- Android 签名：release 包签名由 `android/key.properties`（gitignore，不入库）决定——文件缺失（新 clone、未配 Secrets 的 CI）回退 debug 签名，保证 `flutter run --release` 与静态检查照常可用；文件存在但缺字段则直接构建失败，不静默降级。keystore 在 `android/app/upload-keystore.jks`，**它与口令丢了就永远无法覆盖升级已发布的包**，必须单独备份到仓库之外。CI 从 4 个 Secrets 还原（`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`）。此前 release 用 runner 现生成的 debug 签名，装过旧版的手机因此报「无法安装」——不要退回该状态
- macOS 签名：默认 ad-hoc（`CODE_SIGN_IDENTITY = -` 在 `macos/Runner/Configs/{Debug,Release}.xcconfig`，其末尾的 `#include? "local.xcconfig"` 为可选本机覆盖，include 必须放在默认值**之后**才能让覆盖胜出）。ad-hoc 二进制每次重签 cdhash 都变，而钥匙串条目 ACL 只信任「创建它的那份二进制」——每次重新构建后读「记住凭据」都会弹「想要使用登录钥匙串」授权框（每台主机一条、逐条弹，点「始终允许」只管到下次构建）。本机跑一次 `./tool/setup_dev_codesign.sh` 配置自签证书后经 local.xcconfig 覆盖为证书身份，跨构建稳定、不再弹；旧凭据条目在新身份首次访问时还会弹最后一轮，点「始终允许」即永久安静。Runner target 级**不设** `CODE_SIGN_STYLE`（pbxproj 里三个配置的 Automatic 已摘掉，否则 target 级会压住 local.xcconfig 的 Manual）；CI / 新 clone 没有 local.xcconfig，保持 ad-hoc 不变
- 更新日志：每次合入面向用户的功能或修复，都要在 `CHANGELOG.md` 顶部的「未发布」段补一条（一句话说清变了什么、影响哪端）；发版提交（「版本 x.y.z」）时把「未发布」定稿为版本号 + 日期的段落，再打 tag。纯开发向改动（测试、脚本、CI、文档）不进日志——它是给用户看版本变化的，不是提交记录的复述
- 版本号与版本检测：
  - 版本号**只有一个来源**（宿主包信息经 `app_version.dart` 的 `loadAppVersion()` 读出）：`kFallbackAppVersion` 只是平台通道不可用时垫底的显示值，不是「发版时顺手改一下」的第二个真相。此前它是手写常量，pubspec 到 4.1.3 了界面还显示 4.0.1——「关于」、移动端设置副标题、更新提示的比较基准全跟着错
  - 远端只有 GitHub Releases 一处（仓库坐标在 `update_check_client.dart`），查询走 `dart:io` 的 `HttpClient`（`update_check_io.dart`），**不引 http 包**；web 桩抛 `UnsupportedError`，服务把它归到 `UpdateCheckFailure.unsupported`。桩**绝不**返回「已是最新」——那是把「查不了」谎报成「查过了」，与 web 上 SFTP / 转发的 `unsupported` 路径同一个态度
  - 比较版本号一律用 `isNewerVersion`（按数字段逐位比，不是字符串比；`v` 前缀 / `+构建号` / `-预发布` 都不参与）。任一边解析不出数字段（`dev`、`local`）就返回 false：宁可不说，也不能凭「解析不出来」报一个不存在的新版本
  - 「有新版」的结论要落盘，查询失败**不清**上次的结论（一次网络抖动不该让提示消失），查明确已追平才撤记录。启动静默查询默认延迟 4 秒，已经知道有新版就跳过这次请求
  - UI 落在 `UpdateSettingsRow`（桌面弹窗与移动端 Tab 共用）与设置入口的红点 `UpdateAvailableDot`。分区里**只有一行**：查完之后结果**顶掉那一行的标题**——「检查更新」变成结果本身（绿色「已是最新版本」/ 主色「有新版本 x.y.z」+ 发布日期），颜色本身就是结论的一部分。**不要**再另起一块「检查结果」：行里写「检查更新 / 当前版本」、下面再写「已是最新版本 / 当前版本」，四行说两件事，用户不知道该读哪行（这是返工过一次的地方）。更新说明可能很长，所以它挂在行下按需展开，不塞进那一行
  - 右侧按钮只留一件可做的事：检查（无结论时）/ 重试（可重试的失败）/ 前往下载（有新版本）。查不到发布版或平台不支持时不给「重试」（点多少次都是同样结果），但仍给「检查」，不让按钮凭空消失
  - 「该显示哪种结果」由纯函数 `updateResultViewOf` 判定（标题 / 副标题 / 图标 / 颜色 / 更新说明），widget 只负责画：这一条最容易翻车（查失败被显示成「已是最新」，用户就不再检查了），单独测它比在 widget 树上断文案稳。它判的是「有没有结论」而不是 `status == done`——启动时从落盘读回的结论状态仍是 idle，但同样要展示
  - 更新说明按纯文本渲染（`_plainTextNotes` 去掉 Markdown 标题井号、列表符号换成 `·`）：GitHub 的 release body 是 Markdown，但为此引一个渲染器不值得
  - 测试：`UpdateCheckService` 必须注入假客户端；直接挂 `NoShellApp` 的 widget 测试会自动走 `_NoUpdateCheckClient`（不联网、如实报 notFound），并且**要 `pump` 过 4 秒**，否则那个待触发的计时器会留下悬挂 timer。真实 HTTP 链路的用例只写在 `test/update_check_client_test.dart`（纯 `test` + 本地 `HttpServer`）：组件测试的假时钟推不动真实 socket，`runAsync` 里对本地服务端发请求会挂死（已验证）
- 字体：
  - 终端字体只允许两种来源：随包内置的族，或通用族名 `monospace`。禁止把「系统里可能存在的具体族名」交给渲染——Linux 上 fontconfig 对任何请求名都会返回替代品（可能是比例字体），而终端按固定格子绘字（格宽由 `mmmmmmmmmm` 量出），字形一比例网格就散架；更糟的是主名「命中」了替代品，`fontFamilyFallback` 就永远轮不到
  - 内置族名一律带 `NoShell ` 前缀：与系统字体彻底解耦，引擎必定命中随包文件
  - 新增内置字体：字体与 `OFL.txt` 放 `assets/fonts/<目录>/`（Regular + Bold 两个字重）→ `pubspec.yaml` 的 `fonts:` 声明族名与字重、`assets:` 声明许可文本 → `TerminalFont` 加枚举值 → `kBundledFontLicenses` 登记许可。`test/font_assets_test.dart` 会校验这条链是否接齐
  - 界面字体固定跟随系统，不提供自定义入口（中文字形只有系统字体覆盖得全，界面字体属于原生观感的一部分）
- SFTP 层：
  - SFTP 通道复用会话已认证的 SSH 连接（`SshTransport.openSftp`），不另建 TCP、不重复认证
  - 失败 / 取消只清临时文件，绝不删目标；但进程被强杀时可能留下 `<文件>.noshell-part`（远端那份用户看不见，要手动清）
  - `lib/` 内禁止直接 `import 'dart:io'`；本地文件能力一律走 `ssh/local_write.dart` 的条件导出，web 由桩实现兜底
  - 传输进度只通知 `SftpTransfer` 自身，面板按行订阅；队列结构变化才通知整块面板
  - 删除主机时凭据与指纹一并清理，且**不 await**：钥匙串 / 存储层卡住不能把删除本身拖住（只影响下次连接的判定）。代价是「撤销删除」恢复的主机没有指纹，下次连接按首次记录处理——这是刻意取的舍
  - 上传 / 下载一律**先写临时文件、成功后再改名到目标**（远端与本地同名，都是 `.noshell-part`；本地后缀与远端一致，残留才看得出是谁留下的）：直接往目标上写（远端是 `truncate`）一旦中途失败或取消，用户原有的同名文件就没了；失败与取消只清临时文件，绝不删目标
  - `SftpTransferQueue.dispose()` 只清自己的记录，不打断在跑的传输：`_drain` 与下载循环在 `await` 之后都必须复查 `_disposed` 再改状态或通知，否则会对已 dispose 的 `SftpTransfer` 调 `notifyListeners()`（debug 下直接抛 `used after being disposed`）
  - `_mutate` 的 `isMutating` 必须保持到**刷新结束**才放开：刷新在大目录 / 慢链路上要几百毫秒，提前放开等于允许第二个结构性操作挤进刷新窗口；忙时抛 `SftpErrorKind.busy`，不静默 return（那会让调用方谎报成功）
  - 下载落点数量必须与目标一一对应才开工：网关换了实现（移动端 SAF 选择器）可能少回落点，直接下标取用会在循环中途 RangeError，而前面的任务已经入队
- 状态与重建：
  - `ServerStore` / `SessionManager` 是唯一状态源，UI 通过 `ListenableBuilder` 订阅；通知前必须做无变化守卫，避免下游整页重建
  - 高频交互（搜索输入等）的 `setState` 必须限定在最小子树内，禁止上抛到整页级 State
  - 长列表一律用 `ListView.builder`，行序列先扁平化一次再按下标直取
  - 终端等高频重绘区域必须用 `RepaintBoundary` 隔离
  - `ThemeData` 只在 `AppTheme` 中构建并缓存，禁止在 `build` 方法中新建
  - 传给 xterm 的 `TerminalStyle` 必须按偏好缓存（见 `SshTerminalView._styleOf`）：它没有 `operator ==`，而 painter / render 的守卫都是身份比较，每次 build 新建实例会重测字符宽度并清空 10240 条段落缓存
  - 同理，承载偏好的值类型（`TerminalStylePrefs` / `AppSettings`）必须实现 `==`：`ValueNotifier` 的无变化守卫靠它，否则重复点选同一个预设也会发出通知
  - **改一个偏好的出厂默认值时，必须同时把 `kDefaultsVersion` +1，并在 `AppSettings.fromJson` 里按这个标记决定读法**。为什么不能只靠「缺字段就用新默认」：老版本每次保存设置都会把当时的默认值写进 JSON，字段**不是缺的**，于是新默认对老用户永远不生效（`copyOnSelect` 从关改开后，界面上仍然是关的——踩过一次）
  - 读法是「没带标记 → 给新默认；带了标记 → 原样读回」：老存档里的值分不清是用户的显式选择还是那一代的默认，只能按新默认处理一次；一旦保存过（带上当前标记）就是用户的选择，此后改默认值不再覆盖它
  - 加字段 / 删字段**不用**动 `kDefaultsVersion`——它不是存档格式版本，只回答「这份存档是在哪一代默认值下写出来的」
  - 关窗走 `WindowListener.onWindowClose`：先 `_saveNow()` + `ServerStore.flush()` 再 `destroy()`，否则链式异步落盘的最后一笔改动会随进程退出丢掉
- 导入 / 导出：
  - 界面只暴露一套动作：菜单两项就是「导入主机 / 导出主机」，落在 `.nsbak` 备份文件上；文案不提加密，口令弹窗里才说明口令的作用（`backup*.` 系列文案）
  - 菜单标签不含「备份 / 加密」字样是刻意的：这是应用的主机迁移入口，不是可选项。不要因为内部实现叫 backup 就把菜单文案改回去
  - 标记符 `no-shell-hosts` 是格式的一部分，改动等于让已导出的备份全部失效；它的作用是分开「空备份」与「解出来不是备份」
  - KDF 用 scrypt（N=32768 / r=8 / p=1，约 32 MiB、测试机上约 0.35 秒），不是把 PBKDF2 轮数往上堆：备份明文里是 SSH 密码，派生必须内存硬才有意义，而 PBKDF2 到六十万轮要 2.5 秒、低端设备更久
  - **派生按参数决定要不要 isolate**（见 `HostBackupParams.useIsolate`）：生产参数（N=32768）丢进 `Isolate.run`，0.35 秒的纯 CPU 计算不能冻住界面；测试注入的低参数（N=1024）必须同步算——widget 测试跑在 fake-async 区域里，`Isolate.run` 的 Future 由真实事件循环完成，fake-async 看不见它，`pumpAndSettle` 会一直等到超时（已验证，代价是十分钟挂死）。两条路径的阈值就是 `isolateThreshold`，改参数时注意别把测试拽进 isolate
  - 明文的载体是 `encodeHostsText` 的输出，所以新增主机字段只需改文本格式一处，导入导出同时受益
  - 信封里只放解密必需的参数（`kdf` 及其参数 / `cipher` / `salt` / `nonce`），不写版本号：本项目仍在开发阶段，格式不背历史包袱，只写也只读当前这一种（没有旧 KDF 回退分支）
  - KDF 参数的上下限是防呆：改过的文件不该让 scrypt 吃掉几十 GB 内存
  - 导出落点分两条：桌面端走「另存为」对话框（`LocalDestination.share` 为 false）；移动端没有「另存为」（选择器返回 SAF / 沙盒 URL，`dart:io` 写不进去），写进临时目录后**必须**过 `share_plus` 的分享面板，由用户决定存到「文件」还是发给别人，实现方负责删掉临时文件。不加这道分享，文件就躺在用户找不到的地方
  - SFTP 下载仍走 `pickDownloadTarget`，移动端落到应用文档目录——这条靠 iOS 的 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 才对用户可见，改动 `ios/Runner/Info.plist` 时不要删掉
  - `.nsbak` 的 UTI 是 `com.noshell.hosts-backup`（conforms to `public.json`），在 Info.plist 的 `UTExportedTypeDeclarations` 与 `CFBundleDocumentTypes` 里各声明一次；后缀名改了就三处一起改（`backupFileExtension`、UTI 的 tag、Info.plist）
- 端口转发：
  - 规则是**静态配置**，存在 `SshServer.forwards` 里随主机一起落盘；启停状态属于运行时，挂在主机的活跃会话上（`TerminalSession.forwards`）。没有会话时列表照常展示，但开关禁用并提示先连接
  - 通道复用会话已认证的连接（与 SFTP 同样的取舍）：不另建 TCP、不重复认证，会话断开即随之失效；三种模式的差异只在「哪一头监听」——`-L` 本机监听 + 每个连接开一条直连通道，`-R` 请服务端监听 + 每个入站连接拨到本机，`-D` 交给 dartssh2 的本地 SOCKS5（web 没有原始 TCP，整条路径在 `tunnel_gateway_stub` 处兜底为不支持）
  - `PortForwardRule.isRunnable` 按模式分别判定：动态转发不看远端地址，远程转发的远端端口 0 是「让服务端分配」而不是没填
  - 关掉监听时**不等** `subscription.cancel()` 完成：不再收新连接在调用返回时已生效，等它只会把「用户点了停止」拖在事件循环上
  - 编辑主机时（表单在 `widgets/host_form.dart`，桌面弹窗与移动端编辑页共用）构造 `SshServer` 是**从零拼**（不是 copyWith），必须显式带上 `forwards`，漏掉就是每编辑一次静默清空该主机的全部转发规则；跳板机同理，直接传 `jumpServerId`（null 即清除），别再拼一次 `copyWith(clearJumpServer:)`
- 跳板机：
  - 存的是**跳板机的 id**（`SshServer.jumpServerId`），不是地址副本：跳板机自己也有端口、用户名与凭据，复制一份必然走样；链路在连接时解析（`resolveJumpChain`），环 / 跳板机被删 / 层数超限都在这里挡下并给出可操作的提示
  - 一跳一份凭据：连接流程逐跳取凭据（存过就用，没存过当场弹窗），任意一跳取消即整条连接取消；失败按跳包装成 `SshHopException`，归类与文案用 `unwrapHopError` 剥出真原因，界面必须指明是**哪一跳**出的问题
  - 主机指纹校验逐跳进行：跳板机指纹不一致时，`hostKeyChanged` 带的是那一跳的地址，「清除指纹并重连」清的也必须是那一跳的记录
- 文案（面向专业用户，默认「能删就删」）：
  - `SettingsRow` 的加粗标题说「这是什么」，下面的小字只在**真有信息**时才有：「什么时候用 / 代价是什么 / 会发生什么」。**只有一项的分区不写标题**（标题只会把小字的意思再说一遍）；**开关类不配小字**，「选中即复制」四个字已经说完了这件事，效果一拨自明（这两条都是返工过的地方）
  - 判断标准是「删掉之后用户会不会做错事」。必须留的三类：安全后果（`portForwardExposeWarning`：隧道对全网开放）、数据后果（`backupPasswordWarning`：口令丢了备份就没了）、防回归（`sessionLogHint` 解释「日志是快照不是原始流」，删掉就会有人把原始字节流写进日志）
  - 其余一律压缩，并**保留用户会用来搜索的技术词**（`ssh-rsa`、`ssh-add`、`.nsbak`）——删掉这些词，用户拿着报错信息就搜不到这一项
  - 表单占位符只在**消歧义**时给（host 的「IP 或域名」回答的是「填哪一种」）；字段标签已经说清填什么的，不写举例（`例：web-prod-01` 这类删掉）
  - 不留陈旧的说明：文案跟着功能改，功能改了而说明没改，比没有说明更坏（如结果块里的「可稍后重试」，在重试按钮就摆在那一行之后就是多余信息）
- 颜色一律经 `theme.dart` 的语义色（`AppThemeX` 扩展 / `AppPalette`）获取，不得在组件里散落硬编码颜色
- 任何真实主机凭据、私钥、口令不得写入代码、测试或仓库；冒烟脚本凭据只经命令行传入
- 遵循 `flutter_lints` 规则，新文件需符合官方 Dart 风格；提交前 `flutter analyze` 必须无告警且 `flutter test` 全部通过
