/// 导出前的「挑主机」弹窗：一列复选框，按分组排开，默认全选。
///
/// 桌面端侧边栏与移动端主机页共用同一个「导出主机」流程，所以这里也只有
/// 一份：两端观感一致，只是弹窗宽度受限（窄屏自适应）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../theme.dart';

/// 让用户勾选要导出的主机；返回选中的主机（按传入顺序，也就是侧边栏里的
/// 分组与创建顺序），取消返回 null。
///
/// [groups] 用 `ServerStore.groups()` 的输出：分组顺序与空分组都是那边的语义，
/// 这里只管画。
///
/// 一台都不勾时确认键置灰：导出 0 台主机没有意义，与其事后弹一句
/// 「没有可导出的主机」，不如当场让按钮说不了话。
Future<List<SshServer>?> showHostExportSelection(
  BuildContext context, {
  required List<ServerGroup> groups,
}) {
  return showDialog<List<SshServer>>(
    context: context,
    builder: (_) => _HostExportDialog(groups: groups),
  );
}

class _HostExportDialog extends StatefulWidget {
  const _HostExportDialog({required this.groups});

  final List<ServerGroup> groups;

  @override
  State<_HostExportDialog> createState() => _HostExportDialogState();
}

class _HostExportDialogState extends State<_HostExportDialog> {
  /// 全部候选主机（分组顺序摊平），也是返回值的顺序。
  late final List<SshServer> _servers = [
    for (final group in widget.groups) ...group.servers,
  ];

  /// 勾选中的主机 id。用 id 而不是对象：主机之间没有 `==`，而导入合并
  /// 之后对象可能被换掉，id 才是身份。
  late final Set<String> _selected = {for (final s in _servers) s.id};

  /// 列表行：分组名（String）与主机（SshServer）混排，一次摊平好让
  /// [ListView.builder] 按下标直取。
  late final List<Object> _rows = [
    for (final group in widget.groups)
      if (group.servers.isNotEmpty) ...[group.name, ...group.servers],
  ];

  bool get _allSelected => _selected.length == _servers.length;

  bool get _noneSelected => _selected.isEmpty;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(_servers.map((server) => server.id));
      }
    });
  }

  void _toggle(SshServer server, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _selected.add(server.id);
      } else {
        _selected.remove(server.id);
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop([
      for (final server in _servers)
        if (_selected.contains(server.id)) server,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 弹窗高度跟着屏幕走：矮屏（横屏手机）上别把按钮顶出屏幕。
    final height = math.min(420.0, MediaQuery.sizeOf(context).height * 0.5);
    return AlertDialog(
      title: Text(l10n.exportSelectTitle),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      content: SizedBox(
        width: 320,
        height: height,
        child: Column(
          children: [
            // tristate：全选 / 全不选 / 选了一部分（横杠）。整行都是命中区
            // （勾选框自己忽略指针，只有 InkWell 在收），点一下在「全选」
            // 与「全不选」之间翻——不额外加一颗「全不选」按钮。
            InkWell(
              onTap: _toggleAll,
              child: Row(
                children: [
                  IgnorePointer(
                    child: Checkbox(
                      tristate: true,
                      value: _noneSelected
                          ? false
                          : (_allSelected ? true : null),
                      onChanged: (_) {},
                    ),
                  ),
                  Text(l10n.selectAll),
                  const Spacer(),
                  Text(
                    l10n.exportSelectedCount(_selected.length, _servers.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  if (row is String) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      child: Text(
                        row,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  final server = row as SshServer;
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(server.id),
                    onChanged: (value) => _toggle(server, value),
                    title: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 同名主机靠地址区分：这是它们唯一稳定的差别。
                    subtitle: Text(
                      '${server.username}@${server.host}:${server.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _noneSelected ? null : _confirm,
          child: Text(l10n.exportHosts),
        ),
      ],
    );
  }
}
