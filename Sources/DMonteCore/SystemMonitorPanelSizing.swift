import AppKit

public enum SystemMonitorPanelSizing {
    public static func preferredSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let uiScale = min(1.0, max(0.88, visibleFrame.height / 950))
        let width = min(376, max(338, 370 * uiScale))
        let height = min(316, max(292, 310 * uiScale))

        return NSSize(width: width.rounded(), height: height.rounded())
    }
}
