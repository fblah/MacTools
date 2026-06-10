import AppKit

/// Owns a helper tool's menu-bar status item: installs the icon (or live title) via
/// `StatusBarButtonContent`, routes plain clicks to `primaryAction`, and shows the shared
/// right-click/control-click Quit menu before invoking `quitAction`.
///
/// Replaces the `configureStatusItem()` + `@objc statusItemClicked()` pair previously
/// duplicated in each helper app delegate.
@MainActor
public final class HelperStatusItem: NSObject {
    /// The underlying status item, exposed so tools with live tray content (Keep Awake's
    /// state icon, Focus Timer's countdown title) can keep updating the button.
    public private(set) var item: NSStatusItem?

    private let primaryAction: () -> Void
    private let quitAction: () -> Void

    /// Static-icon variant (`StatusBarButtonContent.install(image:...)`).
    public init(
        image: NSImage,
        toolTip: String,
        primaryAction: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.primaryAction = primaryAction
        self.quitAction = quitAction
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        StatusBarButtonContent.install(
            image: image,
            in: item,
            toolTip: toolTip,
            target: self,
            action: #selector(statusItemClicked)
        )
    }

    /// Live-title variant (`StatusBarButtonContent.install(title:idleImage:...)`), used by
    /// Focus Timer whose button alternates between a countdown string and an idle glyph.
    public init(
        title: String?,
        idleImage: NSImage,
        toolTip: String,
        primaryAction: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.primaryAction = primaryAction
        self.quitAction = quitAction
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        StatusBarButtonContent.install(
            title: title,
            idleImage: idleImage,
            in: item,
            toolTip: toolTip,
            target: self,
            action: #selector(statusItemClicked)
        )
    }

    /// The status item's button, used as the anchor view when positioning panels/windows.
    public var button: NSStatusBarButton? { item?.button }

    @objc private func statusItemClicked() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: item, action: quitAction) {
            return
        }

        primaryAction()
    }

    /// Removes the item from the system status bar (termination teardown).
    public func remove() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }
}
