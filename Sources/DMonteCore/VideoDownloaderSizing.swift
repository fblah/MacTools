import AppKit

public enum VideoDownloaderSizing {
    public static let baseSize = NSSize(width: 410, height: 550)

    public static func preferredSize() -> NSSize {
        let scale = currentScale
        return NSSize(width: (baseSize.width * scale).rounded(), height: (baseSize.height * scale).rounded())
    }

    static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenScale = visibleFrame.height / 1600
        let menuBarScale = NSStatusBar.system.thickness / 26
        return min(1.0, max(0.76, min(screenScale, menuBarScale)))
    }
}
