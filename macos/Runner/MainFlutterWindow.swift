import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
    // 顶部约 28pt 的原生标题栏条仍可拖拽移动窗口。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.titlebarSeparatorStyle = .none
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
