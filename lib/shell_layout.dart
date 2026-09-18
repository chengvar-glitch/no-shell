/// 跨骨架保留的界面状态。
///
/// 窗口宽度跨过 640px 断点时，[LayoutBuilder] 会在桌面左右分栏与移动端底部
/// 导航之间整棵互换骨架——两棵树的 widget 类型不同、没有 key 可用，Element
/// 直接被销毁重建。选中的主机 / 侧边栏折叠态 / 当前 Tab 若留在各自的 State
/// 里，用户每拖一次窗口宽度就丢一次：详情面板跳回空态、Tab 回到第一个。
///
/// 这三个值既不进存档、也不属于任何业务状态源（`ServerStore` 管的是主机与
/// 分组，`SessionManager` 管的是会话），只是「这一屏现在看着哪儿」，
/// 因此单独放一个对象由应用入口持有，两套骨架共用同一份。
final class ShellLayoutState {
  /// 桌面端当前选中的主机 id；没有选中时为空。
  String? selectedId;

  /// 桌面端侧边栏是否整块收起。
  bool sidebarCollapsed = false;

  /// 移动端底部导航当前下标。
  int tab = 0;
}
