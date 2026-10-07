# lib/widgets/AGENTS.md

本目录是桌面端组件，其中大部分（设置面板、主机表单、分组控件、会话菜单、空态、各种弹窗）同时被移动端复用。根 `AGENTS.md` 的全局约定（状态与重建、文案、颜色、l10n、导入导出）继续适用。

**本目录的总纲是「共用件只此一份」**：桌面弹窗与移动端页面外壳不同，字段、校验、构造与观感必须一致。改这里的东西要顺手确认移动端那一侧。

## 组件职责与共用件契约

- `lib/widgets/` — 桌面端组件（侧边栏、详情面板、SFTP 面板、状态徽章）
- `port_forward_panel.dart` — 「转发」页（规则列表 + 新建 / 编辑弹窗），桌面与移动端共用
- `jump_host_field.dart` — 跳板机下拉（桌面弹窗与移动端编辑页共用）
- `sftp_browser.dart` — 库入口，组件按区域拆在同目录的 `sftp_browser_*.dart` part 文件中，外部只可见 `SftpTab`
- `settings_controls.dart` — 设置面板共用件（分组卡片 `SettingsSection` / `SettingsCard` / 设置行 `SettingsRow` / `SettingsIconButton`、各设置控件，以及四个分区的正文 `AppearanceSettingsSection` / `TerminalSettingsSection` / `LanguageSettingsSection` / `ConnectionSettingsSection`，外加「更新」分区的 `UpdateSettingsRow` 与红点 `UpdateAvailableDot`），桌面设置弹窗与移动端设置 Tab 共用同一套，两端观感必须一致，只差配色选择器的形态（宽屏色卡平铺 / 窄屏下拉）
- `host_form.dart` — 主机表单共用件（`HostFormController` 持有输入框、校验与保存时构造 `SshServer`，`HostFormFields` 是字段列，`AuthMethodSelector` 是认证方式三段选择器），桌面编辑弹窗与移动端编辑页共用——两端外壳不同（弹窗 / 整页），字段、校验与主机构造只此一份。**表单里没有「粘贴元数据」入口**（两端都没有，`HostFormDensity` 只管间距 / 字号 / 备注行数 / 输入框有没有「下一项」动作）：主机文本（`key: value` 那种）只在「导入主机」里解析（`host_transfer.dart` → `parseHostsText`），表单逐格输入——此前桌面去掉、移动端保留，后来两端统一去掉，别只在一端加回来。构造 `SshServer` 时**必须显式带上 `forwards` 与 `jumpServerId`**（见 `lib/ssh/AGENTS.md` 的「端口转发」「跳板机」）
- `group_controls.dart` — 分组共用件（分组下拉 `GroupField`——只选已建分组，新建分组走分组菜单；重命名 / 删除 / 移动分组流程 `runGroupAction`；六项菜单的条目表 `groupMenuItems`），桌面侧边栏与移动端主机页共用，两端观感必须一致
- `session_selection.dart` — 详情视图「当前会话 + 会话条数」的无变化守卫 mixin `SessionSelectionGuard`（切会话只发会话层通知，store 那一路重建不起来），桌面详情面板与移动端详情页共用
- `session_idle_view.dart` — 未连接 Tab 的引导空态共用件（图标 + 标题 + 提示 + 可选重连按钮），SFTP Tab 与移动端终端 Tab 共用保持同页空态观感一致，桌面端终端 Tab 仍走终端样式预览（两端刻意不同，见 `TerminalTab.idleStyle`）
- `password_dialog.dart` — 备份口令弹窗（`BackupPasswordMode.create` 设口令并二次确认 / `.open` 输一次口令）
- `host_export_dialog.dart` — 导出前的「挑主机」弹窗 `showHostExportSelection`：按 `store.groups()` 的顺序分组排开（分组名当小标题）、**默认全选**、返回选中的主机列表（取消返回 null），一台都不勾时确认键置灰。三个要点：一是勾选状态用**主机 id** 而不是对象（主机之间没有 `==`）；二是列表先摊平成「分组名 / 主机」混排的一维数组再 `ListView.builder` 按下标直取（长列表的老规矩）；三是顶部那行「全选」用 tristate 复选框（全选 / 全不选 / 选了一部分）+ `IgnorePointer` 包住勾选框、命中区交给外层 `InkWell`——否则点勾选框会同时触发两处、一翻两下等于没翻
- `confirm_dialog.dart` — 确认框 / 说明框 / 轻提示共用件（`showConfirmDialog` 危险确认统一红色实心按钮 / `showInfoDialog` 单键说明框，给「用户得读完才能做对」的失败指引用 / `showToast` 统一轻提示），删除主机、删分组、删转发、删文件等确认一律走它，不要各处自绘。**弹窗一律走 `showAppDialog`**（该文件是唯一直接调 `showDialog` 的地方），它一处管住两条规矩：遮罩不可点关（误点窗口空白处不该把填了一半的表单连窗口一起收走）、Esc 照常关。后者必须自己补——Flutter 把这两件事挂在同一个开关上（`ModalRoute._DismissModalAction.isEnabled` 读的就是 `barrierDismissible`），关掉遮罩误点等于顺手把 Esc 也关掉。补法是弹窗内容外面套一层 `FocusScope(autofocus: true)`：它比框架那层更近，输入框自己的 autofocus 照样落得进去；裸 `CallbackShortcuts` 不行，它不在焦点链上（实测按 Esc 没反应）。不允许中途取消的弹窗（`busy_overlay.dart` 的等待遮罩）传 `escapeDismissible: false`。`test/dialog_dismiss_test.dart` 守这条：`lib/` 里再出现裸 `showDialog` 就变红
- `busy_overlay.dart` — 等待遮罩 `runWithBusyOverlay`（口令弹窗关掉到结果提示之间那段静默：scrypt 派生、逐条读写安全存储）。**慢才现身**（`kBusyShowDelay` 内完成的不闪一下）、**不可取消**（点遮罩与系统返回键都收不掉，护的就是这段窗口）、**抛错也收走**（卡住一层模态遮罩等于锁死界面）。传进去的 `run` 里不许再开路由，选文件 / 输口令的步骤留在遮罩外；结果提示也留在外面（遮罩挡着时 SnackBar 会被压暗）
- `about_dialog.dart` — 「关于」入口（`showAppAboutDialog`，观感与 `showAboutDialog` 一致，只多一层 macOS 适配——许可页自带 AppBar，返回键默认落在红绿灯底下，靠给对话框那层塞让位主题、再被 `showLicensePage` 的 `InheritedTheme.capture` 带进许可页来挪开）

## 相关

- 桌面端骨架 `lib/home_page.dart`（侧边栏 / 详情面板的持有者、主机行单击选中与双击直连、详情 Tab 归 `ShellLayoutState.detailTab`）在 `lib/` 顶层，不在本目录，约定写在根 `AGENTS.md`
