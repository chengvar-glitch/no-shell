/// 分组相关交互的共用件：表单里的分组输入、重命名 / 删除 / 移动分组的弹窗与流程。
/// 桌面端（侧边栏 + 编辑弹窗）与移动端（主机页 + 编辑页）共用同一套，
/// 两端观感与文案必须一致。
library;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'confirm_dialog.dart';

/// 分组选择：只能从已建好的分组里挑，默认分组永远在候选里。
///
/// 表单不再接受手输分组名（旧版一个框既选组又建组，敲个新名字就当场建组）；
/// 新建分组走分组菜单（`runGroupAction` → `promptGroupName`），建好这里就能选到。
/// 控件就是一个官方下拉，不套任何自制外壳。
class GroupField extends StatelessWidget {
  const GroupField({
    super.key,
    required this.value,
    required this.groups,
    required this.onChanged,
  });

  /// 当前选中的分组名，调用方保证非空（空一律由调用方回落到默认分组）。
  final String value;

  /// 已建好的分组名；顺序即用户排过的分组顺序。
  final List<String> groups;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 默认分组恒在候选里（全新安装时它还没入册）；当前值兜一手——主机所属分组
    // 万一不在注册表里，下拉也不会因为找不到选中项而断言失败。Set 字面量按
    // 插入序去重，value 就是默认分组时不会给出两个同值条目。
    final items = <String>{...groups, l10n.defaultGroupName, value}.toList();
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.group),
      items: [
        for (final name in items)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      // 框架的回调签名带可空值，而候选里没有 null 项，直接透传。
      onChanged: (name) {
        if (name != null) onChanged(name);
      },
    );
  }
}

/// 分组头上的动作；桌面弹出菜单与移动端底部弹层各自摆 UI，逻辑走 [runGroupAction]。
enum GroupAction {
  createConnection,
  createGroup,
  rename,
  moveUp,
  moveDown,
  delete,
}

/// 执行一个分组动作。[onCreateInGroup] 由调用方提供（新建连接的入口两端不同）。
Future<void> runGroupAction(
  BuildContext context, {
  required ServerStore store,
  required GroupAction action,
  required String group,
  VoidCallback? onCreateInGroup,
}) async {
  switch (action) {
    case GroupAction.createConnection:
      onCreateInGroup?.call();
    case GroupAction.createGroup:
      final l10n = AppLocalizations.of(context);
      final name = await promptGroupName(
        context,
        title: l10n.groupNew,
        taken: store.groupNames,
      );
      if (name == null) return;
      store.createGroup(name);
    case GroupAction.rename:
      final l10n = AppLocalizations.of(context);
      final name = await promptGroupName(
        context,
        title: l10n.groupRename,
        // 自己不算重名，其余分组都算。
        taken: [
          for (final existing in store.groupNames)
            if (existing != group) existing,
        ],
        initial: group,
      );
      if (name == null) return;
      store.renameGroup(group, name);
    case GroupAction.moveUp:
      store.moveGroup(group, -1);
    case GroupAction.moveDown:
      store.moveGroup(group, 1);
    case GroupAction.delete:
      await deleteGroupFlow(context, store: store, group: group);
  }
}

/// 新建 / 重命名分组的输入弹窗；返回 null 表示取消。
Future<String?> promptGroupName(
  BuildContext context, {
  required String title,
  required Iterable<String> taken,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _GroupNameDialog(title: title, initial: initial, taken: taken.toSet()),
  );
}

/// 删除分组：定好成员去向、二次确认，最后落到 store。
/// 组内还有主机却无处可迁（它是唯一的分组）时不删，只提示。
Future<void> deleteGroupFlow(
  BuildContext context, {
  required ServerStore store,
  required String group,
}) async {
  final l10n = AppLocalizations.of(context);
  final groups = store.groups();
  final index = groups.indexWhere((entry) => entry.name == group);
  if (index == -1) return;
  final count = groups[index].servers.length;
  final others = [
    for (final entry in groups)
      if (entry.name != group) entry.name,
  ];
  // 成员去向：优先默认分组，其次任意其它分组；都没有就只能劝住这次删除。
  final moveTo = others.contains(l10n.defaultGroupName)
      ? l10n.defaultGroupName
      : (others.isEmpty ? group : others.first);
  if (count > 0 && moveTo == group) {
    showToast(context, l10n.groupKeepOne);
    return;
  }
  final confirmed = await confirmDeleteGroup(
    context,
    group: group,
    count: count,
    moveTo: moveTo,
  );
  if (!confirmed || !context.mounted) return;
  store.deleteGroup(group, moveTo: moveTo);
}

Future<bool> confirmDeleteGroup(
  BuildContext context, {
  required String group,
  required int count,
  required String moveTo,
}) {
  final l10n = AppLocalizations.of(context);
  return showConfirmDialog(
    context,
    title: l10n.groupDeleteConfirm(group),
    body: count == 0
        ? l10n.groupDeleteEmptyBody
        : l10n.groupDeleteBody(count, moveTo),
    confirmLabel: l10n.delete,
  );
}

/// 把主机移到另一个分组：选完直接落库；没有别的分组时提示先建一个。
Future<void> moveServerToGroupFlow(
  BuildContext context, {
  required ServerStore store,
  required SshServer server,
}) async {
  final l10n = AppLocalizations.of(context);
  final targets = [
    for (final name in store.groupNames)
      if (name != server.group) name,
  ];
  if (targets.isEmpty) {
    showToast(context, l10n.groupCreateFirst);
    return;
  }
  final target = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(l10n.groupMoveTitle(server.name)),
      children: [
        for (final name in targets)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, name),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: Theme.of(dialogContext).secondaryText,
                ),
                const SizedBox(width: 10),
                Text(name, style: const TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
      ],
    ),
  );
  if (target == null || !context.mounted) return;
  store.upsert(server.copyWith(group: target));
}

/// 分组名输入弹窗：空名或与其它分组重名时禁用「确定」并就地说明原因。
class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({
    required this.title,
    required this.initial,
    required this.taken,
  });

  final String title;
  final String initial;
  final Set<String> taken;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  // 重命名时预选原名字，直接输入即可整体替换。
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _errorOf(AppLocalizations l10n) {
    final text = _controller.text.trim();
    if (text.isEmpty) return l10n.groupNameRequired;
    if (widget.taken.contains(text)) return l10n.groupNameExists;
    return null;
  }

  void _submit() {
    if (_errorOf(AppLocalizations.of(context)) != null) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _errorOf(l10n);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          labelText: l10n.group,
          hintText: l10n.groupHint,
          // 一打开就等着输入，空名不必马上报红；动过之后再提示。
          errorText: _touched ? error : null,
        ),
        onChanged: (_) => setState(() => _touched = true),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: error == null ? _submit : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
