import AppKit
import CoreGraphics

/// Sizing constants for the Maintenance popover, scaled by a single factor so
/// the whole UI can grow/shrink consistently. Mirrors `ClipboardSizing`.
public enum MaintenanceSizing {

    /// Global scale multiplier for the Maintenance UI. Tracks the display height
    /// and menu-bar thickness so the popover shrinks on small screens / thin menu
    /// bars exactly like the other tools (same formula as `ClipboardSizing`).
    public static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenScale = visibleFrame.height / 950
        let menuBarScale = NSStatusBar.system.thickness / 26
        return min(1.0, max(0.82, min(screenScale, menuBarScale)))
    }

    /// Convenience: scale a base point value by `currentScale`.
    public static func s(_ value: CGFloat) -> CGFloat {
        value * currentScale
    }

    // Base (unscaled) metrics.
    public static let basePopoverWidth: CGFloat = 360
    public static let baseHorizontalPadding: CGFloat = 16
    public static let baseVerticalPadding: CGFloat = 14
    public static let baseSectionSpacing: CGFloat = 18
    public static let baseRowSpacing: CGFloat = 10
    public static let baseCornerRadius: CGFloat = 12

    // Scaled accessors.
    public static var popoverWidth: CGFloat { s(basePopoverWidth) }
    public static var horizontalPadding: CGFloat { s(baseHorizontalPadding) }
    public static var verticalPadding: CGFloat { s(baseVerticalPadding) }
    public static var sectionSpacing: CGFloat { s(baseSectionSpacing) }
    public static var rowSpacing: CGFloat { s(baseRowSpacing) }
    public static var cornerRadius: CGFloat { s(baseCornerRadius) }
}
