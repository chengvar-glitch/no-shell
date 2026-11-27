import 'package:flutter/material.dart';

import '../theme.dart';

/// 概览页的布局基元：分区标题、面板与信息网格。
///
/// 概览由三段「标题 + 面板」组成（基础信息 / 备注 / 服务器负载），另加一组
/// 图表卡。它们必须共用同一套内边距、圆角、描边与间距，否则页面会出现
/// 「上面的卡片到这儿断了、下面的面板又是另一个宽度」的割裂感。把这几样
/// 收在这里，改一次就是整页一起改。

/// 面板圆角。
const double kOverviewPanelRadius = 12;

/// 面板内边距（基础信息 / 系统信息 / 备注 / 图表卡共用）。
const EdgeInsets kOverviewPanelPadding = EdgeInsets.all(14);

/// 分区之间的垂直间距。
const double kOverviewSectionGap = 20;

/// 分区标题与下方内容之间的间距。
const double kOverviewHeaderGap = 8;

/// 卡片 / 图表之间的栅格间距。
const double kOverviewGridGap = 12;

/// 概览页的分区标题：左侧标签，右侧可放状态与操作。
///
/// 高度固定 [kSectionHeaderHeight]：标题右侧有时是刷新按钮、有时什么都没有，
/// 高度不一致会让相邻分区的「标题 → 面板」间距看上去忽大忽小。
class OverviewSectionHeader extends StatelessWidget {
  const OverviewSectionHeader({super.key, required this.label, this.trailing});

  static const double kSectionHeaderHeight = 22;

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: kSectionHeaderHeight,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: theme.secondaryText,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 概览页的面板外观（底色 + 圆角 + 描边），宽度默认撑满。
class OverviewPanel extends StatelessWidget {
  const OverviewPanel({
    super.key,
    required this.child,
    this.padding = kOverviewPanelPadding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(kOverviewPanelRadius),
        border: Border.all(color: theme.hairline),
      ),
      child: child,
    );
  }
}

/// 信息网格里的一格：标签 + 值（可带行尾动作，如复制地址）。
@immutable
class OverviewInfoEntry {
  const OverviewInfoEntry({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;

  /// 行尾动作（可选）；[value] 为空时整格不渲染。
  final Widget? trailing;
}

/// 标签 / 值信息网格：基础信息面板与系统信息面板共用。
///
/// 按宽度决定列数，并**固定每格宽度**——这样同一面板里不同行的标签与值
/// 落在同一组垂直基准线上；`Wrap` 默认让每格自己收缩，第一行三格、第二行
/// 两格的参差就是这么来的。
class OverviewInfoPanel extends StatelessWidget {
  const OverviewInfoPanel({super.key, required this.entries});

  final List<OverviewInfoEntry> entries;

  /// 列数：宽屏四列、常规三列、窄一点两列，手机上退化成「标签 — 值」单列列表。
  static int columnsFor(double width) {
    if (width >= 760) return 4;
    if (width >= 540) return 3;
    if (width >= 400) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final entry in entries)
        if (entry.value.isNotEmpty) entry,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return OverviewPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = columnsFor(constraints.maxWidth);
          if (columns == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(height: 9),
                  _InfoRow(entry: visible[i]),
                ],
              ],
            );
          }
          const gap = 24.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: 14,
            children: [
              for (final entry in visible)
                SizedBox(
                  width: width,
                  child: _InfoCell(entry: entry),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 窄屏（单列）用的一行：标签定宽在左，值跟在右，像设置页的键值行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.entry});

  final OverviewInfoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              entry.label,
              style: TextStyle(fontSize: 10.5, color: theme.secondaryText),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              ?entry.trailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// 宽屏（多列）用的一格：标签在上、值在下。
class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.entry});

  final OverviewInfoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, color: theme.secondaryText),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            ?entry.trailing,
          ],
        ),
      ],
    );
  }
}
