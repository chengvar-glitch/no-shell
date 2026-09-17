import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/jump_host.dart';

/// 跳板机选择器：从已保存的主机里挑一台。桌面弹窗与移动端编辑页共用。
///
/// 候选由 [jumpHostCandidates] 过滤：选不出自己，也选不出会连成环的主机。
/// 值为 null 表示直连（不使用跳板机）。
class JumpHostField extends StatelessWidget {
  const JumpHostField({
    super.key,
    required this.servers,
    required this.value,
    required this.onChanged,
    this.self,
  });

  /// 全部已保存的主机（含自己，过滤在内部做）。
  final List<SshServer> servers;

  /// 正在编辑的主机；为 null 表示新建，此时没有「自己」可排除。
  final SshServer? self;

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final candidates = jumpHostCandidates(self, servers);
    // 之前选中的那台可能已经被删 / 已变成不可选（会连成环）：它仍然要出现在
    // 下拉里并保持选中。直接退回「不使用」等于骗人——用户看到的是直连，
    // 存的却还是一台已失效的跳板机，下次连接报的错跟他眼前的界面完全对不上。
    final stale = value != null && !candidates.any((s) => s.id == value);
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.jumpHost,
        helperText: stale ? l10n.jumpHostUnavailable : l10n.jumpHostHint,
        helperMaxLines: 2,
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            l10n.jumpHostNone,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        if (stale)
          DropdownMenuItem<String?>(
            value: value,
            child: Text(
              l10n.jumpHostUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        for (final server in candidates)
          DropdownMenuItem<String?>(
            value: server.id,
            child: Text(
              '${server.name} · ${server.username}@${server.host}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
