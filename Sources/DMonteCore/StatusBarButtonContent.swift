import AppKit

public enum StatusBarButtonContent {
    @MainActor
    public static func install(_ contentView: NSView, in item: NSStatusItem) {
        guard let button = item.button else {
            return
        }

        contentView.frame = button.bounds
        contentView.autoresizingMask = [.width, .height]
        button.addSubview(contentView)

        if let control = contentView as? NSControl {
            control.isEnabled = true
        }
        button.toolTip = contentView.toolTip
    }
}
