import AppKit

public enum CleanDriveSizing {
    public static func preferredSize() -> NSSize {
        let scale = currentScale
        return NSSize(width: (520 * scale).rounded(), height: (680 * scale).rounded())
    }

    static var currentScale: CGFloat {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return min(1.0, max(0.82, visibleFrame.height / 950))
    }
}
