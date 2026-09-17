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

/// 分组输入框：下拉能选已有分组，也能直接输入新名字。
/// 旧版桌面端只有下拉，导致根本建不出第二个分组；这里两端共用同一个控件。
class GroupField extends StatelessWidget {
  const GroupField({
    super.key,
    required this.controller,
    required this.groups,
    this.textStyle,
  });

  final TextEditingController controller;
  final List<String> groups;

  /// 与同表单其它输入框保持同一字号，由调用方按端给。
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownMenu<String>(
      controller: controller,
      // 撑满父宽度，与同列的 TextFormField 对齐。
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      label: Text(l10n.group),
      hintText: l10n.groupHint,
      textStyle: textStyle,
      // DropdownMenu 默认用框架自带的描边白底，不回落到全局输入框主题；
      // 显式传入全局主题，才能与跳板机（DropdownButtonFormField）等
      // 表单字段同观感。样式唯一定义在 theme.dart。
      // 高度钳到 48：浮动标签 + 值两行内容在 dense 主题下正好占满，
      // 与同列单行输入框（用户名等）同高，不再一高一低。
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dropdownMenuEntries: [
        for (final name in groups)
          DropdownMenuEntry<String>(value: name, label: name),
      ],
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
