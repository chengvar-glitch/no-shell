import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/host_key_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../widgets/port_forward_panel.dart' show PortForwardPanel;
import '../widgets/server_detail.dart'
    show OverviewTab, TerminalIdleStyle, TerminalTab;
import '../widgets/session_menu.dart';
import '../widgets/session_selection.dart';
import '../widgets/sftp_browser.dart' show SftpTab;
import '../widgets/status_badges.dart';
import 'server_edit_page.dart';

/// 移动端主机详情页：概览 / 终端 / SFTP / 转发四个 Tab，
/// 复用桌面端的概览、终端、SFTP 与转发视图。
///
/// AppBar 一行收着这台主机的全部状态与动作：主机名、状态胶囊、连接开关
/// （编辑 / 删除在右侧 actions）。连接开关紧跟胶囊，与桌面头部同一顺序。
class ServerDetailPage extends StatefulWidget {
  const ServerDetailPage({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    this.hostKeys,
    required this.serverId,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;

  /// 已记录的主机指纹；删除主机时一并清理，可选（测试可省）。
  final HostKeyStore? hostKeys;
  final String serverId;

  @override
  State<ServerDetailPage> createState() => _ServerDetailPageState();
}

class _ServerDetailPageState extends State<ServerDetailPage>
    with SessionSelectionGuard {
  /// 胶囊自己的 key：会话菜单锚在它下方（与桌面头部、全屏终端页同一套）。
  final GlobalKey _pillKey = GlobalKey();

  @override
  SessionManager get guardedSessions => widget.sessions;

  @override
  String get guardedServerId => widget.serverId;

  @override
  void initState() {
    super.initState();
    startSessionGuard();
  }

  @override
  void didUpdateWidget(ServerDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      rebindSessionGuard(oldWidget.sessions);
    }
    if (oldWidget.serverId != widget.serverId) resyncSessionGuard();
  }

  @override
  void dispose() {
    stopSessionGuard();
    super.dispose();
  }

  void _edit(BuildContext context, SshServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerEditPage(
          store: widget.store,
          credentials: widget.credentials,
          initial: server,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SshServer server) async {
    final index = await confirmAndDeleteHost(
      context,
      store: widget.store,
      sessions: widget.sessions,
      credentials: widget.credentials,
      hostKeys: widget.hostKeys,
      server: server,
    );
    if (index == null || !context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 注意：这里的 store 订阅必须保留——名称 / 状态 / 会话都来自它。
    // 四个 Tab 各自的保活子树已经尽力隔离（见下方 _KeepAlive），
    // 终端那边的重排版由 SshTerminalView 内部的 TerminalStyle 缓存兜住。
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final server = widget.store.byId(widget.serverId);
        if (server == null) {
          // 主机已被删除（或撤销后仍在返回途中），直接展示空态。
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).hostNotFound),
            ),
          );
        }
        final session = widget.sessions.activeOf(server.id);
        final hasActive = session?.isActive ?? false;
        final sessionCount = widget.sessions.sessionsOf(server.id).length;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  key: _pillKey,
                  status: server.status,
                  // 多开了才显示计数与「会话菜单」提示：一条会话时胶囊
                  // 的外观与多会话功能之前完全一样。
                  sessionCount: sessionCount,
                  activeOrdinal: session == null
                      ? 0
                      : widget.sessions.ordinalOf(session),
                  tooltip: sessionCount > 1 ? l10n.sessionMenu : null,
                  onTap: session == null
                      ? null
                      : () => openSessionPill(
                          context,
                          sessions: widget.sessions,
                          server: server,
                          anchor: _pillKey,
                          onNewSession: () => newSessionFlow(
                            context,
                            sessions: widget.sessions,
                            server: server,
                            credentials: widget.credentials,
                            store: widget.store,
                          ),
                        ),
                ),
                // 连接开关紧挨状态胶囊（桌面头部同一顺序）：状态与动作是
                // 同一件事的两面，看一处就够。底部那条常驻按钮随之撤掉——
                // 它把四个 Tab 一起顶高，而手机上这段高度正是终端与文件
                // 列表最缺的。
                //
                // 是**文字按钮**而不是图标：图标时代要长按才知道点下去是
                // 连还是断，而这两个字正是这一行最该说清的事。「连接」两个字
                // 加上 44 的命中区，宽度与原来那颗图标按钮基本一样，主机名
                // 并不会被挤掉一截（它本来就是 Flexible + 省略号）。
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => toggleSession(
                    context,
                    sessions: widget.sessions,
                    server: server,
                    credentials: widget.credentials,
                    // 必须带上 store：跳板机链路是从它解析出来的。
                    store: widget.store,
                  ),
                  style: TextButton.styleFrom(
                    // 44×44 是触屏命中的下限（与分组头那颗「⋯」同一标准）：
                    // 挤到 30 出头看着更贴胶囊，手指却按不准。
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(hasActive ? l10n.disconnect : l10n.connect),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, server),
              ),
              IconButton(
                tooltip: l10n.delete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDelete(context, server),
              ),
            ],
          ),
          body: DefaultTabController(
            length: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  tabs: [
                    Tab(text: l10n.overview),
                    Tab(text: l10n.terminal),
                    Tab(text: l10n.sftp),
                    Tab(text: l10n.portForwarding),
                  ],
                  onTap: (_) => FocusScope.of(context).unfocus(),
                ),
                Expanded(
                  child: TabBarView(
                    // **不跟着手指横滑翻页**，翻页只走上面的 Tab 栏。
                    //
                    // 终端 Tab 里横滑本来该是「拖选区手柄改选区」（手柄拖动
                    // 走的是终端自己的原始 Listener，不参与手势竞技场），而
                    // TabBarView 自带的横向拖动识别器在同一次滑动里会赢下
                    // 竞技场：手柄在动、页面同时也在翻，字就选不准了。终端
                    // 侧在触屏上没有认领横向拖动（xterm 的 pan 识别器只认
                    // 鼠标），拦不住它，只能从这里关掉。
                    //
                    // 桌面端详情面板本来就只有 Tab 栏点按（见 server_detail.dart
                    // 的 _DetailTabView），两端行为因此一致。
                    physics: const NeverScrollableScrollPhysics(),
                    // 保活四个 Tab：切走不再 dispose，切回终端无需重建 xterm 视图。
                    children: [
                      _KeepAlive(
                        child: OverviewTab(
                          server: server,
                          // 跳板机存的是 id，概览要给人看的名字；那台主机已被删时
                          // 名字为空，卡片退回显示 id，让用户看出引用已经失效。
                          jumpHostName: widget.store
                              .byId(server.jumpServerId)
                              ?.name,
                        ),
                      ),
                      _KeepAlive(
                        child: TerminalTab(
                          server: server,
                          session: session,
                          sessions: widget.sessions,
                          idleHint: l10n.sessionMobileHint,
                          // 未连接时不摆黑终端块，与 SFTP Tab 同一形态的空态。
                          idleStyle: TerminalIdleStyle.plain,
                          onRetry: session == null
                              ? null
                              : () => widget.sessions.retry(session),
                          cursorBlink: true,
                        ),
                      ),
                      _KeepAlive(
                        child: SftpTab(
                          session: session,
                          idleHint: l10n.sftpSessionMobileHint,
                          onRetry: session == null
                              ? null
                              : () => widget.sessions.retry(session),
                        ),
                      ),
                      _KeepAlive(
                        child: PortForwardPanel(
                          server: server,
                          store: widget.store,
                          sessions: widget.sessions,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// TabBarView 页面保活包装：共享的 Tab 组件无法逐一改成
/// AutomaticKeepAliveClientMixin，在这里统一声明 wantKeepAlive。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
