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
- SSH 链路冒烟：`dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码>`（或 `--identity <PEM路径>`），追加 `--shell` 验证 PTY、`--sftp` 验证 SFTP 浏览与上传下载链路；凭据只经命令行传入

## 环境与依赖约束

- Dart SDK：`^3.13.3`（见 `pubspec.yaml`）
- Lint 规则：`flutter_lints ^6.0.0`，通过 `analysis_options.yaml` 引入 `package:flutter_lints/flutter.yaml`
- 运行时依赖：`dartssh2 ^4.1.0`（SSH 传输 / SFTP）、`xterm ^4.0.0`（终端渲染）、`file_selector ^1.1.0`（上传选文件、下载另存为）、`path_provider ^2.1.6`（下载默认目录）、`pointycastle ^4.0.0`（加密备份的 PBKDF2 + AES-256-GCM，纯 Dart、六端通用）、`flutter_secure_storage`（凭据安全存储，macOS 需钥匙串 entitlement，已在 entitlements 中配置）、`shared_preferences`（主机列表持久化）、`flutter_localizations` + `intl`（国际化）
- 添加新依赖必须同步更新 `pubspec.yaml` 并重新执行 `flutter pub get`

## 目录结构

- `lib/main.dart` — 应用入口（`NoShellApp`），持有全局状态并按窗口宽度切换桌面/移动骨架
- `lib/host_portable.dart` — 主机文本格式编解码（中英文 key 识别，也用于新建表单的元数据粘贴）；`lib/host_backup.dart` 为备份文件的信封编解码（PBKDF2-HMAC-SHA256 派生密钥 + AES-256-GCM，明文即上面的主机文本，`.nsbak` 后缀）；`lib/host_transfer.dart` 为导入 / 导出用户流程，落盘与合并逻辑只此一份，文件交互经 `LocalFileGateway`
- `lib/models.dart` — `SshServer` 等数据模型与示例数据（含 JSON 序列化）；`ServerGroup` 是渲染用的分组视图（名字 + 成员 + 折叠态）
- `lib/server_persistence.dart` — 主机列表与分组布局落盘通道（`ServerArchive` 快照 + `ServerPersistence` 抽象 + shared_preferences 实现）；主机条目沿用 v1 纯数组格式，分组顺序 / 折叠态另存 `ssh_groups_v1`，旧档按主机出现次序重建分组
- `lib/settings_persistence.dart` — 偏好落盘通道（`AppSettings` 快照：主题 / 语言 / 终端配色·字体·字号；`SettingsPersistence` 抽象 + shared_preferences 实现，枚举按名字存取，脏字段只退回该字段默认值）。已删除的字段（界面字体 `uiFont`、终端自定义字体名）读时忽略、下次保存即抹掉；终端字体的旧取值在 `_terminalFont` 里做一次性迁移（旧系统预设 → `systemMonospace`，旧自定义名 → 内置字体）
- `lib/store.dart` — `ServerStore`（主机列表 + 分组注册表，ChangeNotifier，可选持久化）。分组以「名字」为身份（`SshServer.group` 存的就是分组名），注册表负责顺序、空分组与折叠态，提供 `createGroup` / `renameGroup` / `deleteGroup` / `moveGroup` / `setGroupCollapsed`；落盘串行排队，避免连续变更时旧快照最后落盘
- `lib/theme.dart` — `AppPalette` 色板、`AppTheme` 主题构建（按亮度缓存；界面字体固定跟随系统，`ThemeData` 不再按字体分叉）、`AppThemeX` 语义色扩展
- `lib/settings.dart` — 偏好模型：`TerminalFont`（终端字体目录：族名 / 缺字形回退链 / 名称）、`TerminalPreset`（配色）、`TerminalStylePrefs`（配色 + 字体 + 字号）与 `TerminalStyleScope`；`kBundledFontLicenses` 登记内置字体的 OFL 文本 asset
- `lib/home_page.dart` — 桌面端左右分栏骨架（侧边栏固定宽度、可整体收起，不提供拖拽调宽）
- `lib/widgets/` — 桌面端组件（侧边栏、详情面板、SFTP 面板、状态徽章）；`sftp_browser.dart` 为库入口，组件按区域拆在同目录的 `sftp_browser_*.dart` part 文件中，外部只可见 `SftpTab`；`settings_controls.dart` 为设置面板共用件（分组卡片 `SettingsSection` / `SettingsCard` / 设置行 `SettingsRow` / `SettingsIconButton` 与各设置控件），桌面设置弹窗与移动端设置 Tab 共用同一套，两端观感必须一致；`group_controls.dart` 为分组共用件（可输入新建的分组输入框 `GroupField`、重命名 / 删除 / 移动分组流程 `runGroupAction`），桌面侧边栏与移动端主机页共用，两端观感必须一致；`password_dialog.dart` 为备份口令弹窗（`BackupPasswordMode.create` 设口令并二次确认 / `.open` 输一次口令）
- `lib/ssh/` — 会话层（`SessionManager`、`TerminalSession`、传输层、终端视图、凭据弹窗、连接入口）
  - `credential_store.dart` — 凭据安全存储抽象；`credential_store_io.dart` / `credential_store_stub.dart` 为条件导出的原生实现与 web 桩（同 local_write 模式）
  - `host_key_store.dart` — 主机公钥指纹存储与 TOFU 校验决策（首连记录、变更拒绝）；`HostKeyChangedException` 由会话归类为 `TerminalErrorKind.hostKey`，界面提供「清除记录的指纹并重连」
  - `sftp.dart` / `dartssh2_sftp.dart` — SFTP 领域模型、抽象接口与 dartssh2 适配器
  - `sftp_browser.dart` / `sftp_transfer.dart` — SFTP 面板状态：目录浏览与串行传输队列
  - `local_files.dart` — 本地文件网关（选文件 / 落盘）；`local_write*.dart` 为按平台条件导出的落盘实现
- `lib/mobile/` — 移动端四个 Tab 及详情/编辑页
- `lib/l10n/` — arb 源文件（`app_en.arb` / `app_zh.arb`）；`lib/l10n/generated/` 为生成代码
- `assets/fonts/` — 随包内置的终端字体（`jetbrains_mono/`、`fira_code/` 各含 Regular + Bold 与 `OFL.txt`，合计约 1.2 MB），由 `pubspec.yaml` 的 `fonts:` 声明、`assets:` 声明许可文本。族名一律带 `NoShell ` 前缀（如 `NoShell JetBrains Mono`）：与系统字体彻底解耦，引擎必定命中随包文件
- `test/` — widget、mobile、session_manager、localization、persistence（序列化与持久化）、groups（分组建模 / 排序 / 落盘迁移与两端交互）、credentials_dialog、connect_flow、host_key（TOFU 决策与处置入口）、host_transfer（主机文本格式解析）、host_backup（备份信封与导入 / 导出流程）、sftp（browser / adapter / tab 三组）、window_caption（自绘标题条）、font_assets（内置字体与 pubspec / 许可 / FontManifest 的接线校验）测试；`test/support/` 放共享假实现（含 `FakeCredentialStore`）
- `integration_test/` — 驱动真实应用的集成测试（`screenshots_test.dart` 为 README 截图生成器，演示链路走本地一次性服务端，输出 `docs/screenshots/`）
- `tool/` — 开发脚本（`smoke_ssh.dart` 冒烟脚本，`dev_sftp_server.py` 是配套的一次性本地 SFTP + 假 shell 服务端，只绑 127.0.0.1、账号 smoke/smoke，供 `--sftp` / `--shell` 冒烟与截图使用）
- `docs/screenshots/` — README 截图，由 `integration_test/screenshots_test.dart` 生成，禁止放入真实主机信息
- `icon/` — 应用图标：`art.svg` 是唯一样式来源，`render.py` 生成 `png/` 全套尺寸；iOS / macOS / Windows / Android / Web 由 `dart run flutter_launcher_icons`（配置在 `pubspec.yaml`）写入平台目录，Linux 走 `icon/png/linux/*.png`，由 `release.yml` 装成 hicolor 主题
- `android/` `ios/` `macos/` `linux/` `windows/` `web/` — 六个平台的原生宿主工程；`analysis_options.yaml` 已排除这些目录

## 编辑约定

- 所有应用代码放在 `lib/` 下；不要手改平台目录中的生成文件，除非是插件集成所需的配置（如权限声明）
- `lib/l10n/generated/` 下的文件为生成产物，禁止手改；文案改动一律修改 arb 源文件后执行 `flutter gen-l10n`
- 所有面向用户的文案必须经 `AppLocalizations` 获取，禁止硬编码字符串；新增文案需同时补齐 en/zh 两个 arb
- 平台兼容：代码需同时兼容全部六个平台；web 无原生 TCP，SSH 连接会抛 `UnsupportedError`，依赖 `TerminalErrorKind.unsupported` 归类处理，不得移除该路径
- 字体：
  - 终端字体只允许两种来源：随包内置的族，或通用族名 `monospace`。禁止把「系统里可能存在的具体族名」交给渲染——Linux 上 fontconfig 对任何请求名都会返回替代品（可能是比例字体），而终端按固定格子绘字（格宽由 `mmmmmmmmmm` 量出），字形一比例网格就散架；更糟的是主名「命中」了替代品，`fontFamilyFallback` 就永远轮不到
  - 内置族名一律带 `NoShell ` 前缀：与系统字体彻底解耦，引擎必定命中随包文件
  - 新增内置字体：字体与 `OFL.txt` 放 `assets/fonts/<目录>/`（Regular + Bold 两个字重）→ `pubspec.yaml` 的 `fonts:` 声明族名与字重、`assets:` 声明许可文本 → `TerminalFont` 加枚举值 → `kBundledFontLicenses` 登记许可。`test/font_assets_test.dart` 会校验这条链是否接齐
  - 界面字体固定跟随系统，不提供自定义入口（中文字形只有系统字体覆盖得全，界面字体属于原生观感的一部分）
- SFTP 层：
  - SFTP 通道复用会话已认证的 SSH 连接（`SshTransport.openSftp`），不另建 TCP、不重复认证
  - `lib/` 内禁止直接 `import 'dart:io'`；本地文件能力一律走 `ssh/local_write.dart` 的条件导出，web 由桩实现兜底
  - 传输进度只通知 `SftpTransfer` 自身，面板按行订阅；队列结构变化才通知整块面板
- 状态与重建：
  - `ServerStore` / `SessionManager` 是唯一状态源，UI 通过 `ListenableBuilder` 订阅；通知前必须做无变化守卫，避免下游整页重建
  - 高频交互（搜索输入等）的 `setState` 必须限定在最小子树内，禁止上抛到整页级 State
  - 长列表一律用 `ListView.builder`，行序列先扁平化一次再按下标直取
  - 终端等高频重绘区域必须用 `RepaintBoundary` 隔离
  - `ThemeData` 只在 `AppTheme` 中构建并缓存，禁止在 `build` 方法中新建
- 导入 / 导出：
  - 界面只暴露一套动作：菜单两项就是「导入主机 / 导出主机」，落在 `.nsbak` 备份文件上；文案不提加密，口令弹窗里才说明口令的作用（`backup*.` 系列文案）
  - 菜单标签不含「备份 / 加密」字样是刻意的：这是应用的主机迁移入口，不是可选项。不要因为内部实现叫 backup 就把菜单文案改回去
  - 标记符 `no-shell-hosts` 是格式的一部分，改动等于让已导出的备份全部失效；它的作用是分开「空备份」与「解出来不是备份」
  - 加解密是同步 API：五万轮 PBKDF2 约两三百毫秒，一次导入 / 导出只算一遍；不要改回 `compute` / isolate——`pumpAndSettle` 下会与真 isolate 相互等待而挂死（已验证）
  - 明文的载体是 `encodeHostsText` 的输出，所以新增主机字段只需改文本格式一处，导入导出同时受益
  - 信封里只放解密必需的参数（`kdf` / `iterations` / `cipher` / `salt` / `nonce`），不写版本号：本格式没有历史包袱，不需要为「旧备份」留回退分支
  - `iterations` 上下限是防呆而非兼容：改过的文件不该让解密空转很久
- 颜色一律经 `theme.dart` 的语义色（`AppThemeX` 扩展 / `AppPalette`）获取，不得在组件里散落硬编码颜色
- 任何真实主机凭据、私钥、口令不得写入代码、测试或仓库；冒烟脚本凭据只经命令行传入
- 遵循 `flutter_lints` 规则，新文件需符合官方 Dart 风格；提交前 `flutter analyze` 必须无告警且 `flutter test` 全部通过
