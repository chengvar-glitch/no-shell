<div align="center">

<img src="icon/icon.svg" width="110" alt="NoShell 图标" />

# NoShell

跨平台 SSH 连接管理器：终端、SFTP 文件管理与凭据安全存储，一套 Flutter 代码同时面向桌面与移动端。

[![CI](https://github.com/chengvar-glitch/no-shell/actions/workflows/ci.yml/badge.svg)](https://github.com/chengvar-glitch/no-shell/actions/workflows/ci.yml)
[English](README.md) · **[中文](README_zh.md)**

<img src="docs/screenshots/01-desktop-overview.svg" width="860" alt="NoShell 桌面主界面" />

*桌面端左右分栏：主机分组列表 · 主机概览 · 终端 / SFTP 同屏切换*

</div>

## 功能特性

- **SSH 终端** — 基于 dartssh2 + xterm 的完整交互终端：xterm-256color、自适应尺寸、5 万行滚动回看、密码 / keyboard-interactive / 私钥认证
- **移动端终端手势** — 软键盘上方一条快捷键条（Esc / Tab / 粘滞 Ctrl·Alt / 方向键 / A-·A+ / 鼠标模式，可折叠、窄屏横向滑动）；长按终端弹「复制 / 粘贴 / 全选 / 打开链接」，点链接直达。长按选词后两端各挂一颗手柄，拖动改选区、拖出边界画面跟着滚；双指捏合缩放字号（手势中只出预览，抬手才生效——远端只重排一次）；远端程序开了鼠标上报时点亮「鼠标」，拖动即成为远端的鼠标拖动（vim 可视选区、tmux 拉分割线）。全屏终端页收起 AppBar，轻点顶部一条唤出；右下角「回到最新」一键回到底部，工具栏放大镜搜索回滚内容。移动端
- **同一主机多开会话** — 一台服务器可同时开多条会话，各自独立认证、各自退避重连；状态胶囊显示条数，点开可切换或关闭单条，⊕ 或 ⌘T 再开一条；终端、SFTP 与端口转发跟随当前会话
- **会话日志** — 终端画面（含回滚）的纯文本快照，可复制或另存为 `.log`；快照取自渲染后的缓冲区，配色转义、进度条重画与服务器不回显的密码都不会落进文件
- **SFTP 文件管理** — 目录导航、上传 / 下载（带进度与取消）、重命名、删除、新建目录；常见图片与代码 / 配置文件可快速预览，代码按语法高亮显示；复用已认证的 SSH 连接，不重复建连、不重复认证
- **端口转发** — 每台主机可配本地（-L）/ 远程（-R）/ 动态 SOCKS5（-D）转发规则，在主机详情的「转发」页启停，也可在连接后自动启动；所有隧道复用该主机已认证的 SSH 连接，会话断开即随之失效
- **跳板机（ProxyJump）** — 从已保存的主机里选跳板机，支持多级串联；每一跳各自认证、各自校验主机指纹，终端、SFTP 与端口转发都走同一条链路
- **主机密钥校验（TOFU）** — 首次连接记录服务器公钥指纹，指纹变更时拒绝连接并提供显式清除重连入口，防中间人攻击
- **凭据安全存储** — 勾选「记住凭据」后经系统安全存储加密落盘（macOS 钥匙串 / Windows 凭据管理器 / Linux libsecret），未记住的仅驻留内存
- **主机管理** — 分组、标签、备注、最近连接时间；列表可导出为文本备份，导入时自动识别中英文 key，按「地址+端口+用户」去重合并；新建 / 编辑连接时可直接粘贴同一格式的元数据自动填表，字段仍可手动修改
- **双语界面** — 中英双语，跟随系统或手动指定
- **主题与终端样式** — 明暗主题跟随系统；终端配色预设、随包内置的等宽字体（JetBrains Mono / Fira Code，免安装）与字号可配置
- **版本检测** — 启动后静默查询一次发布页（也可在设置里随时手动检查），有新版本时在设置入口提示并可一键打开发布页；版本号取自安装包本身，不会与应用实际版本不符

## 界面预览

> 截图由 `integration_test/screenshots_test.dart` 驱动真实应用生成（英文界面），演示链路为本机一次性服务端（仅绑定 127.0.0.1），不含任何真实主机信息；上面两张移动端终端图由 `test/mobile_terminal_shot_test.dart` 渲染（组件测试，因此不含系统状态栏与软键盘）。

| 新建连接 | 连接认证 |
| --- | --- |
| <img src="docs/screenshots/02-new-connection.svg" width="420" /> | <img src="docs/screenshots/03-credentials.svg" width="420" /> |

| 终端 | SFTP 文件浏览 |
| --- | --- |
| <img src="docs/screenshots/04-terminal.svg" width="420" /> | <img src="docs/screenshots/05-sftp.svg" width="420" /> |

| 深色主题 | 设置 |
| --- | --- |
| <img src="docs/screenshots/07-dark.svg" width="420" /> | <img src="docs/screenshots/06-settings.svg" width="420" /> |

| 移动端布局（窄屏自动切换底部导航） |
| --- |
| <img src="docs/screenshots/08-mobile.svg" width="300" /> |

| 移动端终端：快捷键条 | 回滚搜索 |
| --- | --- |
| <img src="docs/screenshots/mobile-terminal-keybar.png" width="300" /> | <img src="docs/screenshots/mobile-terminal-search.png" width="300" /> |

## 平台支持

| 平台 | 状态 |
| --- | --- |
| macOS | ✅ 支持（Apple Silicon） |
| Windows | ✅ 支持 |
| Linux | ✅ 支持 |
| Android | ✅ 支持 |
| iOS | ✅ 支持 |
| Web | ⚠️ 已弃用 —— 界面能构建，但 SSH / SFTP 无法工作（浏览器没有原始 TCP），主机导入导出也不可用；不随 Release 发布 |

桌面宽屏（≥640px）为左右分栏布局，窄屏自动切换为移动端底部导航骨架，两端共用同一套数据层与会话层。

## 安装

前往 [Releases](https://github.com/chengvar-glitch/no-shell/releases) 下载对应平台的产物；推送 `v*` 格式的 tag 后，GitHub Actions 会自动构建并发布：

| 平台 | 产物 |
| --- | --- |
| Windows | 免安装 zip |
| macOS | arm64 zip（Apple Silicon） |
| Linux | deb + rpm（安装到 `/opt/noshell`，含桌面入口；带 GPG 签名，验证方式见下） |
| Android | APK |

Linux 的 deb / rpm 均带 GPG 签名。CI 在每次发布时现生成一次性密钥：私钥随构建环境销毁，公钥即该次 Release 附带的 `NoShell-<tag>-linux-signing.asc`。验证（把 `<tag>` 换成实际版本，公钥用同一 Release 附带的那份）：

```bash
# deb：分离签名
gpg --import NoShell-<tag>-linux-signing.asc
gpg --verify NoShell-<tag>-linux-amd64.deb.asc NoShell-<tag>-linux-amd64.deb

# rpm：内嵌签名
rpmkeys --import NoShell-<tag>-linux-signing.asc
rpm -K NoShell-<tag>-linux-x86_64.rpm
```

## 从源码构建

```bash
flutter pub get
flutter run -d macos   # 或 -d windows / linux / chrome / <device-id>
```

## 开发

```bash
flutter analyze                 # 静态分析（提交前必须无告警）
flutter test                    # 全部测试
flutter test test/xxx_test.dart # 单个测试文件
dart format <文件>              # 格式化改动的文件
flutter gen-l10n                # 修改 arb 文案后重新生成
```

SSH 链路冒烟（需要真实主机凭据时，凭据只经命令行传入，不写入仓库）：

```bash
dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码>            # 终端链路
dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码> --sftp     # SFTP 链路
dart run tool/smoke_ssh.dart <host> <port> <user> --password <密码> --shell    # PTY 链路
```

端口转发 + 跳板机冒烟（走 App 自己的会话层连真实主机；没给环境变量时自动跳过，
因此 `flutter test` 默认仍然是全绿）：

```bash
NOSHELL_SMOKE_HOST=<主机> NOSHELL_SMOKE_PASSWORD=<密码> \
  flutter test test/forward_smoke_test.dart
```

### 重新生成 README 截图

```bash
# 1. 启动本机一次性演示服务端（仅绑定 127.0.0.1，账号 smoke/smoke）
#    它依赖 asyncssh；用一次性 venv 装，别污染系统 Python：
python3 -m venv /tmp/sftp-venv && /tmp/sftp-venv/bin/pip install asyncssh
/tmp/sftp-venv/bin/python tool/dev_sftp_server.py /tmp/demo-root 2222

# 2. 驱动真实应用逐屏截图，PNG 输出到 docs/screenshots/
flutter test integration_test/screenshots_test.dart -d macos
```

> PNG 写入应用工作目录下的 `docs/screenshots`；想让它们落到别处，用 `SSH_SHOTS_DIR` 指定绝对路径。

## 架构速览

- `lib/ssh/` — 会话层：传输抽象（`SshTransport`）与 dartssh2 适配、TOFU 指纹存储（`host_key_store.dart`）、SFTP 抽象与适配、凭据安全存储、端口转发运行时（`port_forward_runtime.dart`）与跳板链路解析（`jump_host.dart`）
- `lib/store.dart` + `lib/server_persistence.dart` — 主机列表状态与落盘
- `lib/widgets/`、`lib/mobile/` — 桌面分栏骨架与移动端 Tab 骨架
- `lib/l10n/` — arb 源文件（en / zh），生成代码在 `lib/l10n/generated/`
- `test/` — widget、会话、SFTP、持久化、本地化等单元与组件测试；`test/support/` 为共享假实现
- `integration_test/` — 驱动真实应用的集成测试：README 截图生成器，以及在模拟器 / 真机上跑「连接 → 终端 → SFTP → 断开」全流程的移动端自测
- `tool/` — 开发脚本：SSH 链路冒烟（`smoke_ssh.dart`）与本地一次性演示服务端（`dev_sftp_server.py`）

平台相关能力统一走条件导出（web 由桩实现兜底），`lib/` 内不直接依赖 `dart:io`。

## 安全模型

- 私钥与密码只存于系统安全存储；未勾选「记住凭据」时仅驻留内存
- 主机公钥指纹按 TOFU 原则记录于本地；指纹不一致时连接被拒绝，须用户显式确认后才清除旧记录
- 主机密钥指纹不是机密，与主机列表同级存储；任何真实凭据不得进入代码、测试或仓库
- 版本检测是唯一会主动联网的功能：启动后延迟数秒向 GitHub 查询本项目的最新发布版，请求不含任何主机、凭据或使用数据。除此之外应用不发送任何遥测

## 许可

以 [Apache License 2.0](LICENSE) 授权，署名信息见 [NOTICE](NOTICE)。

随包内置的终端字体（JetBrains Mono、Fira Code）以 SIL Open Font License 1.1 授权，许可文本随应用分发（`assets/fonts/*/OFL.txt`），并与全部 Dart / Flutter 依赖的许可一起列在「关于 → 查看许可」里。
