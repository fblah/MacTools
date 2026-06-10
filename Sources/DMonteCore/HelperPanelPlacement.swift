import Foundation

/// Pure frame math shared by the helper tools' panel/window hosts.
///
/// Every helper app used to carry private copies of `centeredWindowFrame(for:)` /
/// `windowFrame(for:near:)` / `panelFrame(for:)`; this is the single shared
/// implementation. It is deliberately free of `NSView`/`NSWindow` dependencies so the
/// clamping math can be unit-tested.
public enum HelperPanelPlacement {
    /// The visible frame the helpers have always assumed when no screen information is
    /// available (headless edge case).
    public static let fallbackVisibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

    /// Inset kept between a positioned panel/window and the screen's visible-frame edges.
    public static let screenEdgeInset: CGFloat = 8

    /// A frame of `size` centered in `visibleFrame` (the historic fallback when there is no
    /// status-item anchor to position near).
    public static func centeredFrame(for size: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    /// A frame of `size` horizontally centered under `anchorFrame` (a status-item button in
    /// screen coordinates), dropped `gap` points below it, clamped so it stays
    /// `screenEdgeInset` points inside `visibleFrame` on the left/right/bottom edges.
    ///
    /// Matches the math previously duplicated across the helper delegates: when the panel
    /// is wider than the available space the right-edge clamp wins, and a panel that would
    /// fall below the screen is pinned `screenEdgeInset` above the bottom edge.
    public static func anchoredFrame(
        for size: NSSize,
        anchorFrame: NSRect,
        visibleFrame: NSRect,
        gap: CGFloat = 8
    ) -> NSRect {
        let x = min(
            max(anchorFrame.midX - (size.width / 2), visibleFrame.minX + screenEdgeInset),
            visibleFrame.maxX - size.width - screenEdgeInset
        )
        let y = max(visibleFrame.minY + screenEdgeInset, anchorFrame.minY - size.height - gap)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The unclamped origin centered under `anchorFrame` (used when no screen is known to
    /// clamp against — Color Picker's historic behaviour).
    public static func unclampedAnchoredOrigin(
        for size: NSSize,
        anchorFrame: NSRect,
        gap: CGFloat
    ) -> NSPoint {
        NSPoint(
            x: anchorFrame.midX - (size.width / 2),
            y: anchorFrame.minY - size.height - gap
        )
    }

    /// The top-right-corner fallback origin (Maintenance's historic behaviour when the
    /// status-item anchor cannot be resolved).
    public static func topRightOrigin(for size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.maxX - size.width - screenEdgeInset,
            y: visibleFrame.maxY - size.height - screenEdgeInset
        )
    }
}
