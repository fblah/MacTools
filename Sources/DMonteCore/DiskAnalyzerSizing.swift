import AppKit

public enum DiskAnalyzerSizing {
    public static func preferredSize() -> NSSize {
        let scale = currentScale
        return NSSize(width: (720 * scale).rounded(), height: (640 * scale).rounded())
    }

    static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return min(1.0, max(0.78, visibleFrame.height / 950))
    }
}
