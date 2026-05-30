import AppKit
import ApplicationServices

/// A window-snapping action. The raw value is a stable identifier used for hotkey registration
/// and persistence; `title` / `symbol` drive the UI.
public enum WindowAction: String, CaseIterable, Sendable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case firstTwoThirds, lastTwoThirds
    case maximize, center, almostMaximize

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .firstTwoThirds: "Left Two-Thirds"
        case .lastTwoThirds: "Right Two-Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        case .almostMaximize: "Almost Maximize"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .leftThird: "rectangle.lefthalf.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.righthalf.filled"
        case .firstTwoThirds: "rectangle.lefthalf.inset.filled"
        case .lastTwoThirds: "rectangle.righthalf.inset.filled"
        case .maximize: "rectangle.fill"
        case .center: "rectangle.center.inset.filled"
        case .almostMaximize: "rectangle.inset.filled"
        }
    }

    /// Default keyboard shortcut, as (Carbon key code, Carbon modifier mask). All snap shortcuts
    /// use ⌃⌥ (Control+Option) like Rectangle's defaults, which rarely clash with app shortcuts.
    public var defaultShortcut: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .leftHalf: (HotKeyCode.left, HotKeyModifier.controlOption)
        case .rightHalf: (HotKeyCode.right, HotKeyModifier.controlOption)
        case .topHalf: (HotKeyCode.up, HotKeyModifier.controlOption)
        case .bottomHalf: (HotKeyCode.down, HotKeyModifier.controlOption)
        case .maximize: (HotKeyCode.returnKey, HotKeyModifier.controlOption)
        case .center: (HotKeyCode.c, HotKeyModifier.controlOption)
        default: nil
        }
    }
}

/// Carbon virtual key codes used for the default shortcuts.
public enum HotKeyCode {
    public static let left: UInt32 = 0x7B
    public static let right: UInt32 = 0x7C
    public static let down: UInt32 = 0x7D
    public static let up: UInt32 = 0x7E
    public static let returnKey: UInt32 = 0x24
    public static let c: UInt32 = 0x08
}

/// Carbon modifier masks (mirrors Carbon's `controlKey`/`optionKey` without importing Carbon here).
public enum HotKeyModifier {
    public static let controlOption: UInt32 = 0x1000 /* controlKey */ | 0x0800 /* optionKey */
}

/// Window-snapping logic. The geometry is **pure and fully testable**: `frame(for:in:)` takes a
/// usable area and returns the target rect, both in a top-left origin space (x grows right, y grows
/// down — the same space AppKit's Accessibility API uses). The actual reading/writing of a window's
/// position lives in `WindowController`, which converts AppKit's bottom-left screen coordinates to
/// this space at the boundary and applies the result through the Accessibility API.
public enum WindowManagerKit {

    /// Computes the target frame for `action` within `area` (a top-left-origin rect: y grows down).
    /// Pure arithmetic — no global state — so it is exhaustively unit-tested.
    public static func frame(for action: WindowAction, in area: CGRect) -> CGRect {
        let x = area.minX
        let y = area.minY
        let w = area.width
        let h = area.height
        let halfW = w / 2
        let halfH = h / 2
        let thirdW = w / 3

        switch action {
        case .leftHalf:        return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf:       return CGRect(x: x + halfW, y: y, width: w - halfW, height: h)
        case .topHalf:         return CGRect(x: x, y: y, width: w, height: halfH)
        case .bottomHalf:      return CGRect(x: x, y: y + halfH, width: w, height: h - halfH)
        case .topLeft:         return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .topRight:        return CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH)
        case .bottomLeft:      return CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH)
        case .bottomRight:     return CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH)
        case .leftThird:       return CGRect(x: x, y: y, width: thirdW, height: h)
        case .centerThird:     return CGRect(x: x + thirdW, y: y, width: thirdW, height: h)
        case .rightThird:      return CGRect(x: x + 2 * thirdW, y: y, width: w - 2 * thirdW, height: h)
        case .firstTwoThirds:  return CGRect(x: x, y: y, width: 2 * thirdW, height: h)
        case .lastTwoThirds:   return CGRect(x: x + thirdW, y: y, width: w - thirdW, height: h)
        case .maximize:        return area
        case .center:
            // Center at 60% size, clamped so it never exceeds the area.
            let cw = min(w, w * 0.6)
            let ch = min(h, h * 0.6)
            return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
        case .almostMaximize:
            let inset = min(w, h) * 0.05
            return CGRect(x: x + inset, y: y + inset, width: w - 2 * inset, height: h - 2 * inset)
        }
    }
}
