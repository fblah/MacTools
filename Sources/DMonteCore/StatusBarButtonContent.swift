import AppKit

/// Configures a menu-bar `NSStatusItem`'s own button as the icon host, rather than adding a
/// custom subview to it.
///
/// Two earlier bugs both trace back to the custom-subview approach:
///   • The button was left with no image/title of its own, so when the menu bar got crowded
///     during normal use macOS treated it as empty and culled it — the icon "disappeared."
///   • A hand-drawn image blitted into a subview via `NSImage.draw(in:)` keeps its baked color,
///     so the toolbox glyph rendered solid black instead of the adaptive template white the
///     SF-symbol tools get.
///
/// Driving the button natively fixes both: a template image is auto-tinted (white on a dark
/// menu bar), gets the standard rollover highlight for free, and is AppKit-managed content that
/// the menu bar won't drop. `target`/`action` (set by the caller) handle the click.
public enum StatusBarButtonContent {
    private final class MenuAction: NSObject {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }

    /// Installs a static template icon on the status item's button.
    /// - Parameters:
    ///   - image: the icon; forced to template so AppKit tints + highlights it.
    ///   - item: the status item whose button hosts the icon.
    ///   - toolTip: hover tooltip.
    ///   - target/action: click handler wired to the button itself.
    @MainActor
    public static func install(
        image: NSImage,
        in item: NSStatusItem,
        toolTip: String,
        target: AnyObject,
        action: Selector
    ) {
        guard let button = item.button else { return }
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Installs a button driven by a live string (e.g. Focus Timer's countdown). Pass the icon
    /// used when `title` is empty/idle. Call `updateTitle` again whenever the value changes.
    @MainActor
    public static func install(
        title: String?,
        idleImage: NSImage,
        in item: NSStatusItem,
        toolTip: String,
        target: AnyObject,
        action: Selector
    ) {
        guard let button = item.button else { return }
        idleImage.isTemplate = true
        button.toolTip = toolTip
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateTitle(title, idleImage: idleImage, in: item)
    }

    /// Switches the button between a text title and the idle icon. AppKit tints/highlights both.
    @MainActor
    public static func updateTitle(_ title: String?, idleImage: NSImage, in item: NSStatusItem) {
        guard let button = item.button else { return }
        if let title, !title.isEmpty {
            button.image = nil
            button.title = title
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .noImage
        } else {
            idleImage.isTemplate = true
            button.title = ""
            button.image = idleImage
            button.imagePosition = .imageOnly
        }
    }

    /// Shows a lightweight right-click context menu for a status item while preserving the
    /// normal left-click action used by popovers/windows.
    @MainActor
    public static func popUpQuitMenuIfNeeded(
        for item: NSStatusItem?,
        additionalItems: [(title: String, action: () -> Void)] = [],
        quitTitle: String = "Quit",
        action: @escaping () -> Void
    ) -> Bool {
        guard let eventType = NSApp.currentEvent?.type,
              eventType == .rightMouseDown || eventType == .rightMouseUp,
              let item,
              let button = item.button else {
            return false
        }

        let menu = NSMenu()
        for additionalItem in additionalItems {
            let handler = MenuAction(action: additionalItem.action)
            let menuItem = NSMenuItem(title: additionalItem.title, action: #selector(MenuAction.performAction), keyEquivalent: "")
            menuItem.target = handler
            menuItem.representedObject = handler
            menu.addItem(menuItem)
        }
        if !additionalItems.isEmpty {
            menu.addItem(.separator())
        }

        let handler = MenuAction(action: action)
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(MenuAction.performAction), keyEquivalent: "")
        quitItem.target = handler
        quitItem.representedObject = handler
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.minY), in: button)
        return true
    }
}
