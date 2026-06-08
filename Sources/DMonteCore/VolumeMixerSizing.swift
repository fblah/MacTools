import AppKit
import CoreGraphics

public enum VolumeMixerSizing {
    public static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenScale = visibleFrame.height / 950
        let menuBarScale = NSStatusBar.system.thickness / 26
        return min(1.0, max(0.82, min(screenScale, menuBarScale)))
    }

    public static func s(_ value: CGFloat) -> CGFloat {
        value * currentScale
    }

    public static func preferredSize() -> NSSize {
        NSSize(width: panelWidth.rounded(), height: panelHeight.rounded())
    }

    public static var panelWidth: CGFloat { s(490) }
    public static var panelHeight: CGFloat { s(620) }
    public static var outerPadding: CGFloat { s(16) }
    public static var sectionSpacing: CGFloat { s(12) }
    public static var rowSpacing: CGFloat { s(6) }
    public static var rowVerticalPadding: CGFloat { s(8) }
    public static var rowHorizontalPadding: CGFloat { s(12) }
    public static var rowCornerRadius: CGFloat { s(10) }
    public static var titleSize: CGFloat { s(15) }
    public static var sectionHeaderSize: CGFloat { s(12) }
    public static var bodySize: CGFloat { s(13) }
    public static var captionSize: CGFloat { s(11) }
    public static var checkmarkSize: CGFloat { s(13) }
    public static var scrollMaxHeight: CGFloat { s(476) }
}
