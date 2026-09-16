import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 红绿灯偏移（相对窗口左上角），单位是「红绿灯单位」= 单个灯的外框宽。
  private let trafficLightLeftUnits: CGFloat = 1.5
  private let trafficLightTopUnits: CGFloat = 1.25

  /// 红绿灯（关闭 / 最小化 / 最大化）的原始坐标。系统会随窗口布局重排标题栏
  /// 按钮，平移必须以这份原始坐标为基准做绝对定位，重复触发才不会累加偏移。
  private var baseTrafficLightOrigins: [NSWindow.ButtonType: NSPoint] = [:]

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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 平移红绿灯：close 灯的左上角对齐到 trafficLightLeftUnits / TopUnits
  /// 定义的偏移，其余两灯保持系统给的相对间距一起移动。坐标只在偏离目标
  /// 时回写，避免 set 布局值再触发一轮无意义的失效循环。
  private func repositionTrafficLights() {
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
    let unit = closeButton.frame.width
    // 按钮坐标挂在标题条容器里，容器原点不在窗口原点，换算到窗口坐标
    //（to: nil 即窗口坐标，原点左下、y 向上）再差值，消除父视图偏移。
    let containerOrigin = closeButton.superview?.convert(
      NSPoint.zero, to: nil
    ) ?? .zero
    let dx = trafficLightLeftUnits * unit - (containerOrigin.x + base.x)
    let desiredY = frame.height - trafficLightTopUnits * unit
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
