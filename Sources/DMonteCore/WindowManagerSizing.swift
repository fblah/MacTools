import AppKit

public enum WindowManagerSizing {
    public static func preferredSize() -> NSSize {
        // 380×560: wide enough for the shortcut rows ("In use by macOS…" notices) and tall
        // enough that the collapsible Keyboard Shortcuts section is reachable without feeling
        // cramped; the content scrolls, so smaller screens still work via the scale clamp.
        let scale = currentScale
        return NSSize(width: (380 * scale).rounded(), height: (560 * scale).rounded())
    }

    static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenScale = visibleFrame.height / 950
        let menuBarScale = NSStatusBar.system.thickness / 26
        return min(1.0, max(0.82, min(screenScale, menuBarScale)))
    }
}
