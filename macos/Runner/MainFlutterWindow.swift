import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 红绿灯（关闭灯）左上角相对窗口左上角的偏移，单位 pt。
  /// 左边距 21pt 约等于 1.5 个灯位；Flutter 侧与红绿灯齐平的行高
  /// （sidebar / server_detail 的 54）= 上边距 + 半个灯高的两倍，改动需同步。
  private let trafficLightLeftInset: CGFloat = 21
  private let trafficLightTopInset: CGFloat = 20

  /// 红绿灯（关闭 / 最小化 / 最大化）的原始坐标。系统会随窗口布局重排标题栏
  /// 按钮，平移必须以这份原始坐标为基准做绝对定位，重复触发才不会累加偏移。
  private var baseTrafficLightOrigins: [NSWindow.ButtonType: NSPoint] = [:]

  /// 是否处于全屏。全屏时红绿灯的隐藏与唤出（鼠标移到屏幕顶部）交给系统
  /// 管理，平移不再介入；窗口态才按 trafficLightLeftInset / TopInset 校对位置。
  private var isInFullScreen = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 初始 1536x960（旧版 1280x800 放大 20%，保持 16:10），并限制最小可用尺寸。
    // 屏幕可用区域装不下时按比例收缩并留边，避免低分辨率机器上窗口超出屏幕。
    let preferredSize = NSSize(width: 1536, height: 960)
    let minimumSize = NSSize(width: 940, height: 600)
    let screenInset: CGFloat = 32
    var availableSize = preferredSize
    if let visibleSize = NSScreen.main?.visibleFrame.size,
       visibleSize.width > 0, visibleSize.height > 0 {
      availableSize = NSSize(
        width: max(1, visibleSize.width - screenInset),
        height: max(1, visibleSize.height - screenInset))
    }
    let windowSize = NSSize(
      width: min(preferredSize.width, availableSize.width),
      height: min(preferredSize.height, availableSize.height))
    self.setContentSize(windowSize)
    self.center()
    // 最小尺寸不能超过实际窗口，否则小屏上无法继续收缩。
    self.minSize = NSSize(
      width: min(minimumSize.width, windowSize.width),
      height: min(minimumSize.height, windowSize.height))

    // 隐藏标题栏文字与底色，仅保留红绿灯；内容延伸至标题栏区域，
    // 顶部条带（含下面挂的空工具栏）的拖拽、点击回归系统原生管理。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.titlebarSeparatorStyle = .none
    self.styleMask.insert(.fullSizeContentView)

    // 挂一条空工具栏把标题条带加高到 52pt（.unified）：红绿灯平移出默认
    // 32pt 条带后必须留在条带界内才收得到点击（NSView 命中测试不进入越界
    // 子视图），直接改容器尺寸会跟 AppKit 的标题栏布局打架，由系统管理的
    // 条带高度才是稳的；透明背景下条带本身不可见。
    let toolbar = NSToolbar(identifier: "NoShellTitlebarToolbar")
    toolbar.displayMode = .iconOnly
    self.toolbar = toolbar
    self.toolbarStyle = .unified

    // 红绿灯默认贴着窗口左上角，按 trafficLightLeftUnits / TopUnits 定义的
    // 「红绿灯单位」偏移量平移。AppKit 在窗口每轮更新里都会重排标题栏按钮，
    // 因此订阅 didUpdate 校对回目标位置。
    NotificationCenter.default.addObserver(
      forName: NSWindow.didUpdateNotification, object: self, queue: .main
    ) { [weak self] _ in
      self?.repositionTrafficLights()
    }

    // 全屏时摘掉空工具条：窗口态它负责把标题条带撑高，红绿灯平移后才收得到
    // 点击；全屏里这条条带却以不透明材质绘制，正好盖住内容顶部一行（Flutter
    // 的头部按钮整行被盖掉），平移到条带区间里的红绿灯也被压在材质之下，
    // 连同系统「鼠标移到顶部唤出红绿灯」一起失效。进全屏前摘除、退出时恢复，
    // 全屏期间的红绿灯显示与唤出完全交给系统。
    NotificationCenter.default.addObserver(
      forName: NSWindow.willEnterFullScreenNotification, object: self,
      queue: .main
    ) { [weak self] _ in
      self?.setFullScreenChrome(true)
    }
    NotificationCenter.default.addObserver(
      forName: NSWindow.willExitFullScreenNotification, object: self,
      queue: .main
    ) { [weak self] _ in
      self?.setFullScreenChrome(false)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 全屏进出时切换标题条带：进入摘掉工具条（并停用红绿灯平移），退出恢复。
  /// 挂回工具条要在恢复平移之前，条带先回到 52pt，平移过去的红绿灯才接得到点击。
  private func setFullScreenChrome(_ enters: Bool) {
    isInFullScreen = enters
    if enters {
      self.toolbar = nil
    } else {
      let toolbar = NSToolbar(identifier: "NoShellTitlebarToolbar")
      toolbar.displayMode = .iconOnly
      self.toolbar = toolbar
      self.toolbarStyle = .unified
    }
  }

  /// 平移红绿灯：close 灯的左上角对齐到 trafficLightLeftUnits / TopUnits
  /// 定义的偏移，其余两灯保持系统给的相对间距一起移动。坐标只在偏离目标
  /// 时回写，避免 set 布局值再触发一轮无意义的失效循环。
  /// 全屏期间不介入：红绿灯的隐藏与唤出由系统管理，平移过去只会压在
  /// 全屏的标题条带材质之下，看起来就是「红绿灯消失」。
  private func repositionTrafficLights() {
    if isInFullScreen { return }
    let types: [NSWindow.ButtonType] = [
      .closeButton, .miniaturizeButton, .zoomButton,
    ]
    if baseTrafficLightOrigins.isEmpty {
      for type in types {
        if let button = standardWindowButton(type) {
          baseTrafficLightOrigins[type] = button.frame.origin
        }
      }
    }
    guard let base = baseTrafficLightOrigins[.closeButton],
          let closeButton = standardWindowButton(.closeButton) else { return }
    // 按钮坐标挂在标题条容器里，容器原点不在窗口原点，换算到窗口坐标
    //（to: nil 即窗口坐标，原点左下、y 向上）再差值，消除父视图偏移。
    let containerOrigin = closeButton.superview?.convert(
      NSPoint.zero, to: nil
    ) ?? .zero
    let dx = trafficLightLeftInset - (containerOrigin.x + base.x)
    let desiredY = frame.height - trafficLightTopInset
      - closeButton.frame.height
    let dy = desiredY - (containerOrigin.y + base.y)
    for type in types {
      guard let button = standardWindowButton(type),
            let origin = baseTrafficLightOrigins[type] else { continue }
      let target = NSPoint(x: origin.x + dx, y: origin.y + dy)
      if button.frame.origin != target {
        button.setFrameOrigin(target)
      }
    }
  }
}
