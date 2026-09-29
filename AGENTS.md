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
- 运行时依赖：`dartssh2 ^4.1.0`（SSH 传输 / SFTP）、`xterm ^4.0.0`（终端渲染；**实际取的是仓库内打了补丁的 `third_party/xterm`**，由 `dependency_overrides` 挂上，见 `lib/ssh/AGENTS.md` 的「终端输入」条）、`url_launcher ^6.3.2`（终端里的链接与发布页交给系统浏览器打开）、`file_selector ^1.1.0`（上传选文件、下载另存为）、`share_plus ^13.3.0`（移动端导出的系统分享面板）、`path_provider ^2.1.6`（下载默认目录 / 导出临时目录）、`pointycastle ^4.0.0`（加密备份的 scrypt + AES-256-GCM，纯 Dart、六端通用）、`ffi ^2.1.0`（只用于绑 libc 的 chmod，导出备份收到 0600）、`flutter_secure_storage`（凭据安全存储，macOS 需钥匙串 entitlement，已在 entitlements 中配置）、`shared_preferences`（主机列表持久化）、`package_info_plus ^10.2.1`（读宿主包信息拿真实版本号，见 `app_version.dart`）、`flutter_localizations` + `intl`（国际化）
- 添加新依赖必须同步更新 `pubspec.yaml` 并重新执行 `flutter pub get`

## 目录结构

**本文件是全局约定，两个子目录各带一份就近约定**：编辑 `lib/ssh/` 或 `lib/widgets/` 下的文件时，同目录的 `AGENTS.md` 会一并生效，那里是终端交互、会话层、共用件契约的踩坑记录——本文件不再重复它们。

- `lib/main.dart` — 应用入口（`NoShellApp`），持有全局状态并按窗口宽度切换桌面/移动骨架
- `lib/host_portable.dart` — 主机文本格式编解码（中英文 key 识别，也用于移动端新建表单的元数据粘贴）；`lib/host_backup.dart` 为备份文件的信封编解码（scrypt 派生密钥 + AES-256-GCM，明文即上面的主机文本，`.nsbak` 后缀）；`lib/host_transfer.dart` 为导入 / 导出用户流程，落盘与合并逻辑只此一份，文件交互经 `LocalFileGateway`
- `lib/models.dart` — `SshServer` 等数据模型与示例数据（含 JSON 序列化）；`ServerGroup` 是渲染用的分组视图（名字 + 成员 + 折叠态）
- `lib/server_persistence.dart` — 主机列表与分组布局落盘通道（`ServerArchive` 快照 + `ServerPersistence` 抽象 + shared_preferences 实现）；主机条目与分组布局各存一个 key。`load()` 返回 `ServerArchiveLoad` 三态（`Missing` / `Loaded` / `Unreadable`）而不是可空存档：「没有存档」与「存档读不出来」必须分开，否则后者会被当成首次运行、随即被空列表覆盖掉。只读当前格式，不做旧档迁移
- `lib/settings_persistence.dart` — 偏好落盘通道（`AppSettings` 快照：主题 / 语言 / 终端配色·字体·字号；`SettingsPersistence` 抽象 + shared_preferences 实现，枚举按名字存取）。单个字段认不出来只退回该字段默认值，不让一条脏数据带走整份偏好；不认得的字段读时忽略、下次保存即被抹掉——开发阶段不做版本号也不做旧字段迁移
- `lib/store.dart` — `ServerStore`（主机列表 + 分组注册表，ChangeNotifier，可选持久化）。分组以「名字」为身份（`SshServer.group` 存的就是分组名），注册表负责顺序、空分组与折叠态，提供 `createGroup` / `renameGroup` / `deleteGroup` / `moveGroup` / `setGroupCollapsed`；落盘串行排队，避免连续变更时旧快照最后落盘。存档不可读时置 `archiveUnreadable` 并**停写**（`_schedulePersist` 直接返回）：此时内存列表是残缺的，落盘等于抹掉用户仅存的数据；该状态由设置页顶部的 `ArchiveWarningCard` 告知用户
- `lib/theme.dart` — `AppPalette` 色板、`AppTheme` 主题构建（按亮度缓存；界面字体固定跟随系统，`ThemeData` 不再按字体分叉）、`AppThemeX` 语义色扩展
- `lib/settings.dart` — 偏好模型：`TerminalFont`（终端字体目录：族名 / 缺字形回退链 / 名称）、`TerminalPreset`（配色）、`TerminalStylePrefs`（配色 + 字体 + 字号）与 `TerminalStyleScope`；`kBundledFontLicenses` 登记内置字体的 OFL 文本 asset
- `lib/app_version.dart` + `lib/update_check*.dart` — 软件版本检测。`app_version.dart` 的 `appVersion` 是**可变全局**（启动时由 `loadAppVersion()` 从 `package_info_plus` 写入，读不到才退回常量 `kFallbackAppVersion`），因为「关于」与设置页都在同步的 `build` 里取它。`update_check_client.dart` 是纯 Dart 的模型与版本比较（六端通用），`update_check_io.dart` / `_stub.dart` 是 `dart:io` 的 `HttpClient` 实现与 web 桩，`update_check_state.dart` 是唯一状态源 `UpdateCheckService`，`update_launcher*.dart` 负责把发布页交给系统浏览器。UI 共用件是 `widgets/settings_controls.dart` 里的 `UpdateSettingsRow` 与 `UpdateAvailableDot`
- `lib/home_page.dart` — 桌面端左右分栏骨架（侧边栏固定宽度、可整体收起，不提供拖拽调宽）。主机行交互：单击选中、**双击直连**（选中 + 发起连接 + 详情面板落到终端 Tab；已连接时双击只跳转不断开——双击是「给我终端」，不是连接开关）。详情面板当前 Tab 下标归 `ShellLayoutState.detailTab`（外部入口改写它、用户点 Tab 写回它），双击检测在 tile 里自己量点击间隔，**不许**把 `onDoubleTap` 挂上同一块 InkWell——框架的双击手势会把单击在竞技场里扣住 300ms 才放行，单击选中跟着迟钝（与 `terminal_view.dart` 链接点击自收指针事件是同一类取舍）
- `lib/widgets/` — 桌面端组件（侧边栏、详情面板、SFTP 面板、状态徽章、设置与表单共用件等）。**各组件职责与「共用件只此一份」的契约见 `lib/widgets/AGENTS.md`**
- `lib/ssh/` — 会话层（`SessionManager`、`TerminalSession`、传输层、终端视图、凭据弹窗、连接入口、转发与跳板机）。**终端交互、凭据存储、主机指纹、SFTP、端口转发、跳板机的踩坑记录见 `lib/ssh/AGENTS.md`**
- `lib/mobile/` — 移动端四个 Tab 及详情/编辑页
- `lib/l10n/` — arb 源文件（`app_en.arb` / `app_zh.arb`）；`lib/l10n/generated/` 为生成代码
- `assets/fonts/` — 随包内置的终端字体（`jetbrains_mono/`、`fira_code/` 各含 Regular + Bold 与 `OFL.txt`，合计约 1.2 MB），由 `pubspec.yaml` 的 `fonts:` 声明、`assets:` 声明许可文本。族名一律带 `NoShell ` 前缀（如 `NoShell JetBrains Mono`）：与系统字体彻底解耦，引擎必定命中随包文件
- `test/` — widget、mobile、session_manager、localization、persistence（序列化与持久化）、groups（分组建模 / 排序 / 落盘迁移与两端交互）、credentials_dialog、connect_flow、host_key（TOFU 决策与处置入口）、host_transfer（主机文本格式解析）、host_backup（备份信封与导入 / 导出流程）、busy_overlay（等待遮罩的延迟现身 / 不可取消 / 抛错也收走）、sftp（browser / adapter / tab 三组）、window_caption（自绘标题条）、font_assets（内置字体与 pubspec / 许可 / FontManifest 的接线校验）、port_forward（规则模型 + 三种模式的运行时）、port_forward_panel（转发页交互）、jump_host（链路解析 / 候选过滤 / 逐跳失败归类 / 连接流程弹窗）、ssh_agent（agent 协议 / 身份映射 / 会话归类）、update_check（版本比较 / GitHub 查询 / 状态与设置页交互）测试；`terminal_key_bar_test.dart` 覆盖移动端快捷键条、粘滞修饰键的输入变换、触屏长按 / 点链接 / 鼠标模式 / 捏合缩放；`terminal_ime_test.dart` 覆盖中文输入法上屏的去重（经 `TestTextInput` 走真实的平台消息，见 `lib/ssh/AGENTS.md` 的「终端输入」条）与软键盘弹起 / 收起时不带着终端重排（见 `lib/ssh/AGENTS.md` 的键盘保持条）；`mobile_terminal_shot_test.dart` 生成移动端终端截图（默认跳过，见 `docs/screenshots/`）；`forward_smoke_test.dart` / `agent_smoke_test.dart` 是需要真实主机的冒烟（无环境变量时自动跳过）；`test/support/` 放共享假实现（含 `FakeCredentialStore`、`forward_fakes.dart` 里的假通道 / 假网关 / 假转发传输）
- `integration_test/` — 驱动真实应用的集成测试：`screenshots_test.dart` 为 README 截图生成器（演示链路走本地一次性服务端，输出 `docs/screenshots/`），`mobile_connect_test.dart` 在模拟器 / 真机上跑移动端「连接 → 终端 → 键条 / 长按菜单 / 选区手柄 / 查找 / 捏合 → SFTP → 断开」全流程（手势那一段**按平台门控**：本测试也允许在 macOS 桌面上跑，而键条与手柄只在 iOS / Android 挂载，桌面端不该因此变红）。两者都要真机或模拟器，不进 CI；缺前置时自动跳过
- `tool/` — 开发脚本（`install_local_linux.sh` 把 `build/linux/x64/release/bundle` 按 release.yml 的 deb 布局装到本机（`/opt/noshell` + `/usr/local/bin/noshell` + hicolor 图标 + 桌面入口，需 sudo）；`smoke_ssh.dart` 冒烟脚本，`dev_sftp_server.py` 是配套的一次性本地 SFTP + 假 shell 服务端，只绑 127.0.0.1、账号 smoke/smoke，供 `--sftp` / `--shell` 冒烟与截图使用；`setup_dev_codesign.sh` 为 macOS 本机开发证书签名的一次性配置脚本）
- `docs/screenshots/` — README 截图，由 `integration_test/screenshots_test.dart` 生成；`mobile-terminal-*.png` 三张是**用 Flutter 自己渲染**的移动端终端截图，由 `test/mobile_terminal_shot_test.dart` 生成（`NOSHELL_SHOT=1 flutter test --update-goldens test/mobile_terminal_shot_test.dart`）。该用例默认 `skip`：golden 对字体栅格化敏感，换台机器逐像素比就会「失败」，这里要的是「生成一张能看的图」而不是把平台差异钉进 `flutter test`。测试环境没有系统字体，截图前得手动喂三样东西——随包 JetBrains Mono（终端）、Roboto + Droid Sans Fallback 叠在同一个族里（界面：**前者只有拉丁、后者只有 CJK，缺一个就是满屏方块**）、MaterialIcons（图标）。禁止放入真实主机信息
- `docs/prototypes/` — 设计评审用的交互原型图（`mobile-terminal-ux.png`）与其渲染脚本 `render.py`（Pillow 直绘，无第三方依赖；`python3 docs/prototypes/render.py` 重跑）。只给人看布局，不参与构建、不进版本日志
- `icon/` — 应用图标：`art.svg` 是唯一样式来源，`render.py` 生成 `png/` 全套尺寸；iOS / macOS / Windows / Android / Web 由 `dart run flutter_launcher_icons`（配置在 `pubspec.yaml`）写入平台目录，Linux 走 `icon/png/linux/*.png`，由 `release.yml` 装成 hicolor 主题
- `third_party/xterm/` — 打了补丁的 xterm 副本（MIT，只留 `lib/` 与许可），由根 `pubspec.yaml` 的 `dependency_overrides` 挂上。补丁内容、为什么必须 fork、上游修好后怎么撤，都写在 `third_party/README.md`；`analysis_options.yaml` 已排除该目录
- `android/` `ios/` `macos/` `linux/` `windows/` `web/` — 六个平台的原生宿主工程；`analysis_options.yaml` 已排除这些目录。macOS **未开 App Sandbox**：沙盒下钥匙串访问组必须通过 application-identifier（团队签名）校验，而项目无 Apple 团队（ad-hoc，TeamIdentifier=not set），$(AppIdentifierPrefix) 展开为空，flutter_secure_storage 读写一律 -34018；同时 macOS 侧 `MacOsOptions.usesDataProtectionKeychain` 必须为 false（数据保护钥匙串同样要求团队签名）。恢复沙盒的前提是接入 DEVELOPMENT_TEAM 并逐项重验凭据链路（本机开发的证书签名与钥匙串授权弹窗问题见编辑约定「macOS 签名」条）

## 编辑约定

- 所有应用代码放在 `lib/` 下；不要手改平台目录中的生成文件，除非是插件集成所需的配置（如权限声明）
- `lib/l10n/generated/` 下的文件为生成产物，禁止手改；文案改动一律修改 arb 源文件后执行 `flutter gen-l10n`
- 所有面向用户的文案必须经 `AppLocalizations` 获取，禁止硬编码字符串；新增文案需同时补齐 en/zh 两个 arb
- 平台兼容：代码需同时兼容全部六个平台；web 无原生 TCP，SSH 连接会抛 `UnsupportedError`，依赖 `TerminalErrorKind.unsupported` 归类处理，不得移除该路径
- `lib/` 内禁止直接 `import 'dart:io'`；本地文件能力一律走条件导出（详见 `lib/ssh/AGENTS.md` 的「SFTP 层」）
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
  - 「原样读回」的阈值必须锚在**该字段自己的变更代**（如 `kCopyOnSelectDefaultsVersion`），不能拿全局 `kDefaultsVersion` 比较：阈值随全局浮动的话，将来为其他字段改默认值把全局 +1，这一代用户的显式选择会被误判成旧档默认、静默重置回出厂值（审查抓到的 latent bug）
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
- 文案（面向专业用户，默认「能删就删」）：
  - `SettingsRow` 的加粗标题说「这是什么」，下面的小字只在**真有信息**时才有：「什么时候用 / 代价是什么 / 会发生什么」。**只有一项的分区不写标题**（标题只会把小字的意思再说一遍）；**开关类不配小字**，「选中即复制」四个字已经说完了这件事，效果一拨自明（这两条都是返工过的地方）
  - 判断标准是「删掉之后用户会不会做错事」。必须留的三类：安全后果（`portForwardExposeWarning`：隧道对全网开放）、数据后果（`backupPasswordWarning`：口令丢了备份就没了）、防回归（`sessionLogHint` 解释「日志是快照不是原始流」，删掉就会有人把原始字节流写进日志）
  - 其余一律压缩，并**保留用户会用来搜索的技术词**（`ssh-rsa`、`ssh-add`、`.nsbak`）——删掉这些词，用户拿着报错信息就搜不到这一项
  - 表单占位符只在**消歧义**时给（host 的「IP 或域名」回答的是「填哪一种」）；字段标签已经说清填什么的，不写举例（`例：web-prod-01` 这类删掉）
  - 不留陈旧的说明：文案跟着功能改，功能改了而说明没改，比没有说明更坏（如结果块里的「可稍后重试」，在重试按钮就摆在那一行之后就是多余信息）
- 颜色一律经 `theme.dart` 的语义色（`AppThemeX` 扩展 / `AppPalette`）获取，不得在组件里散落硬编码颜色
- 任何真实主机凭据、私钥、口令不得写入代码、测试或仓库；冒烟脚本凭据只经命令行传入
- 遵循 `flutter_lints` 规则，新文件需符合官方 Dart 风格；提交前 `flutter analyze` 必须无告警且 `flutter test` 全部通过
