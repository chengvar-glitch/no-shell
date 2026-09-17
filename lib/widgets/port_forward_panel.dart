import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/port_forward_runtime.dart';
import '../ssh/session_manager.dart';
import '../ssh/ssh_transport.dart';
import '../store.dart';
import '../theme.dart';
import 'confirm_dialog.dart';

/// 转发类型的三字母标记（-L / -R / -D），列表里当图标用。
String forwardModeBadge(PortForwardMode mode) => switch (mode) {
  PortForwardMode.local => 'L',
  PortForwardMode.remote => 'R',
  PortForwardMode.dynamic => 'D',
};

/// 转发类型的展示名。
String forwardModeLabel(AppLocalizations l10n, PortForwardMode mode) =>
    switch (mode) {
      PortForwardMode.local => l10n.portForwardModeLocal,
      PortForwardMode.remote => l10n.portForwardModeRemote,
      PortForwardMode.dynamic => l10n.portForwardModeDynamic,
    };

/// 一条规则在列表里的摘要（桌面端与移动端一致）。
String forwardSummary(AppLocalizations l10n, PortForwardRule rule) {
  final listen = '${rule.localHost}:${rule.localPort}';
  final target = '${rule.remoteHost}:${rule.remotePort}';
  return switch (rule.mode) {
    PortForwardMode.local => l10n.portForwardSummaryLocal(listen, target),
    PortForwardMode.remote => l10n.portForwardSummaryRemote(target, listen),
    PortForwardMode.dynamic => l10n.portForwardSummaryDynamic(listen),
  };
}

/// 端口转发面板：桌面端详情 Tab 与移动端详情 Tab 共用同一套。
///
/// 规则是静态配置，存在 [ServerStore] 里；启停状态属于运行时，
/// 挂在主机的活跃会话上（[PortForwardManager]）。没有会话就只读展示规则，
/// 开关禁用并给出提示——转发通道必须有一条已认证的连接可挂。
class PortForwardPanel extends StatelessWidget {
  const PortForwardPanel({
    super.key,
    required this.server,
    required this.store,
    required this.sessions,
  });

  final SshServer server;
  final ServerStore store;
  final SessionManager sessions;

  @override
  Widget build(BuildContext context) {
    final session = sessions.byServerId(server.id);
    final manager = session?.forwards;
    // 三方都要订阅：规则来自 store，会话有无来自 sessions，启停状态来自会话的
    // 转发管理器。合并成一个 Listenable 交给同一个 builder，避免嵌套重建。
    return ListenableBuilder(
      listenable: Listenable.merge([store, sessions, ?manager]),
      builder: (context, _) =>
          _buildBody(context, store.byId(server.id) ?? server, manager),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SshServer server,
    PortForwardManager? manager,
  ) {
    final rules = server.forwards;
    final connected = manager != null;
    if (rules.isEmpty) {
      return _EmptyState(onCreate: () => _edit(context, server, null));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  connected
                      ? AppLocalizations.of(context).portForwarding
                      : AppLocalizations.of(context).portForwardSessionHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).secondaryText,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _edit(context, server, null),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(AppLocalizations.of(context).portForwardAdd),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RuleCard(
                  rule: rule,
                  status: manager?.statusOf(rule.id),
                  connected: connected,
                  onToggle: manager == null
                      ? null
                      // 参数是「开关拨到的新状态」，不是「当前是否在跑」：
                      // 打开就启、关掉就停。写反的话点一下等于按下停止键。
                      : (enabled) => enabled
                            ? manager.start(rule)
                            : manager.stop(rule.id),
                  onEdit: () => _edit(context, server, rule),
                  onDelete: () => _delete(context, server, rule, manager),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    SshServer server,
    PortForwardRule? existing,
  ) async {
    final result = await showForwardRuleDialog(context, existing: existing);
    if (result == null) return;
    // 不碰 context：弹窗关闭后这颗 BuildContext 可能已经失效，
    // 而这个写入只依赖 store，跨异步缺口用它没有任何必要。
    _replaceRule(server, result);
  }

  /// 覆盖写入一条规则：同 id 替换，新 id 追加。
  void _replaceRule(SshServer server, PortForwardRule rule) {
    final rules = [...server.forwards];
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index == -1) {
      rules.add(rule);
    } else {
      rules[index] = rule;
    }
    store.upsert(server.copyWith(forwards: rules));
  }

  Future<void> _delete(
    BuildContext context,
    SshServer server,
    PortForwardRule rule,
    PortForwardManager? manager,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.portForwardDeleteTitle,
      body: l10n.portForwardDeleteBody,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !context.mounted) return;
    // 先发停止、再删规则：留着一条没人再点得到的隧道比删掉更糟。
    // 不等它收尾——关监听要等套接字真的关完（异步），而规则本身应当
    // 立刻从列表里消失，没必要排在套接字后面。
    unawaited(manager?.stop(rule.id) ?? Future<void>.value());
    store.upsert(
      server.copyWith(
        forwards: [
          for (final item in server.forwards)
            if (item.id != rule.id) item,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: theme.panelBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.hairline),
            ),
            child: Icon(
              Icons.alt_route_rounded,
              size: 26,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.portForwardEmpty,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.portForwardEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(l10n.portForwardAdd),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.status,
    required this.connected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final PortForwardRule rule;
  final PortForwardStatus? status;
  final bool connected;

  /// 启停动作，参数是开关拨到的新状态（true = 启动）；为 null 表示没有
  /// 会话可挂（开关禁用）。
  final Future<void> Function(bool enabled)? onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final phase = status?.phase ?? PortForwardPhase.stopped;
    final running = phase == PortForwardPhase.running;
    final color = switch (phase) {
      PortForwardPhase.running => theme.statusColor(ServerStatus.connected),
      PortForwardPhase.starting => theme.statusColor(ServerStatus.connecting),
      PortForwardPhase.failed => theme.statusColor(ServerStatus.error),
      PortForwardPhase.stopped => theme.secondaryText,
    };
    final statusLabel = switch (phase) {
      PortForwardPhase.starting => l10n.portForwardStatusStarting,
      PortForwardPhase.running => l10n.portForwardStatusRunning,
      PortForwardPhase.failed => l10n.portForwardStatusFailed,
      PortForwardPhase.stopped => l10n.portForwardStatusStopped,
    };
    final boundPort = status?.boundPort;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ModeBadge(label: forwardModeBadge(rule.mode)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      forwardSummary(l10n, rule),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                        if (boundPort != null &&
                            boundPort != rule.localPort) ...[
                          const SizedBox(width: 8),
                          Text(
                            l10n.portForwardBoundPort(boundPort),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.secondaryText,
                            ),
                          ),
                        ],
                        if (rule.autoStart) ...[
                          const SizedBox(width: 8),
                          _Tag(label: l10n.portForwardAutoTag),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: running,
                onChanged: connected && onToggle != null
                    ? (value) => onToggle!(value)
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              IconButton(
                tooltip: l10n.edit,
                onPressed: onEdit,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                icon: Icon(Icons.edit_outlined, color: theme.secondaryText),
              ),
              IconButton(
                tooltip: l10n.delete,
                onPressed: onDelete,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppPalette.danger,
                ),
              ),
            ],
          ),
          if (phase == PortForwardPhase.failed) ...[
            const SizedBox(height: 6),
            Text(
              forwardErrorText(l10n, status!),
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppPalette.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 转发启动失败的可读文案：按归类挑一句，原始错误串留在后面备查。
String forwardErrorText(AppLocalizations l10n, PortForwardStatus status) {
  final message = switch (status.errorKind) {
    ForwardErrorKind.notConnected => l10n.portForwardErrorNotConnected,
    ForwardErrorKind.unsupported => l10n.portForwardErrorUnsupported,
    ForwardErrorKind.refused => l10n.portForwardErrorRefused,
    ForwardErrorKind.network => l10n.portForwardErrorNetwork,
    ForwardErrorKind.other || null => l10n.portForwardErrorOther,
  };
  final detail = status.error;
  return detail == null || detail.isEmpty ? message : '$message\n$detail';
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.hoverOverlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: theme.hoverOverlay,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: theme.secondaryText),
      ),
    );
  }
}

/// 新建 / 编辑转发规则的弹窗；桌面端与移动端共用，返回 null 表示取消。
Future<PortForwardRule?> showForwardRuleDialog(
  BuildContext context, {
  PortForwardRule? existing,
}) => showDialog<PortForwardRule>(
  context: context,
  builder: (_) => _ForwardRuleDialog(existing: existing),
);

class _ForwardRuleDialog extends StatefulWidget {
  const _ForwardRuleDialog({this.existing});

  final PortForwardRule? existing;

  @override
  State<_ForwardRuleDialog> createState() => _ForwardRuleDialogState();
}

class _ForwardRuleDialogState extends State<_ForwardRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late PortForwardMode _mode = widget.existing?.mode ?? PortForwardMode.local;
  late final _localHost = TextEditingController(
    text: widget.existing?.localHost ?? '127.0.0.1',
  );
  late final _localPort = TextEditingController(
    text: _initialPort(widget.existing?.localPort),
  );
  late final _remoteHost = TextEditingController(
    text: widget.existing?.remoteHost ?? '127.0.0.1',
  );
  late final _remotePort = TextEditingController(
    text: _initialPort(widget.existing?.remotePort),
  );
  late bool _autoStart = widget.existing?.autoStart ?? false;

  /// 端口 0 是「还没填」，编辑时不该显示成 0；远程转发允许 0（服务端分配）。
  static String _initialPort(int? port) =>
      port == null || port == 0 ? '' : '$port';

  @override
  void dispose() {
    for (final controller in [
      _localHost,
      _localPort,
      _remoteHost,
      _remotePort,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validatePort(String? value, {required bool allowZero}) {
    final l10n = AppLocalizations.of(context);
    final port = int.tryParse((value ?? '').trim());
    if (port == null) return l10n.portInvalid;
    if (allowZero && port == 0) return null;
    if (port < 1 || port > 65535) return l10n.portInvalid;
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final remote = int.tryParse(_remotePort.text.trim()) ?? 0;
    Navigator.of(context).pop(
      PortForwardRule(
        id:
            widget.existing?.id ??
            'fwd-${DateTime.now().microsecondsSinceEpoch}',
        mode: _mode,
        localHost: _localHost.text.trim(),
        localPort: int.tryParse(_localPort.text.trim()) ?? 0,
        remoteHost: _remoteHost.text.trim(),
        remotePort: _mode == PortForwardMode.dynamic ? 0 : remote,
        autoStart: _autoStart,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dynamic = _mode == PortForwardMode.dynamic;
    final description = switch (_mode) {
      PortForwardMode.local => l10n.portForwardLocalDesc,
      PortForwardMode.remote => l10n.portForwardRemoteDesc,
      PortForwardMode.dynamic => l10n.portForwardDynamicDesc,
    };
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.portForwardAdd : l10n.portForwardEdit,
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<PortForwardMode>(
                  segments: [
                    ButtonSegment(
                      value: PortForwardMode.local,
                      label: Text(l10n.portForwardModeLocal),
                    ),
                    ButtonSegment(
                      value: PortForwardMode.remote,
                      label: Text(l10n.portForwardModeRemote),
                    ),
                    ButtonSegment(
                      value: PortForwardMode.dynamic,
                      label: Text(l10n.portForwardModeDynamic),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  // 类型决定字段含义（哪一侧是监听、哪一侧是目标），
                  // 改类型时把已填的端口留在原位，用户不必重新输一遍。
                  onSelectionChanged: (selection) =>
                      setState(() => _mode = selection.first),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: theme.secondaryText),
                ),
                const SizedBox(height: 14),
                _AddressRow(
                  hostController: _localHost,
                  portController: _localPort,
                  hostLabel: l10n.portForwardListenAddress,
                  portLabel: l10n.portForwardListenPort,
                  hostHint: l10n.portForwardAddressRequired,
                  portValidator: (value) =>
                      _validatePort(value, allowZero: false),
                ),
                if (!dynamic) ...[
                  const SizedBox(height: 14),
                  _AddressRow(
                    hostController: _remoteHost,
                    portController: _remotePort,
                    hostLabel: l10n.portForwardTargetAddress,
                    portLabel: l10n.portForwardTargetPort,
                    hostHint: l10n.portForwardAddressRequired,
                    // 远程转发的目标端口允许 0：交给服务端挑一个空闲端口。
                    portValidator: (value) => _validatePort(
                      value,
                      allowZero: _mode == PortForwardMode.remote,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                SwitchListTile(
                  value: _autoStart,
                  onChanged: (value) => setState(() => _autoStart = value),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    l10n.portForwardAutoStart,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    l10n.portForwardAutoStartHint,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}

/// 地址 + 端口一行：两栏比例固定，窄屏（移动端弹窗）也不会挤成一团。
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.hostController,
    required this.portController,
    required this.hostLabel,
    required this.portLabel,
    required this.hostHint,
    required this.portValidator,
  });

  final TextEditingController hostController;
  final TextEditingController portController;
  final String hostLabel;
  final String portLabel;
  final String hostHint;
  final String? Function(String?) portValidator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: hostController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: hostLabel,
              hintText: hostHint,
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? l10n.portForwardAddressRequired
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: portController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(labelText: portLabel),
            validator: portValidator,
          ),
        ),
      ],
    );
  }
}
