import AppKit
import SwiftUI
import DMonteCore

// MARK: - Keyable panel

/// A borderless, non-activating panel that can still become key so SwiftUI
/// controls (buttons, toggles) respond on first click. Mirrors the Clipboard
/// `KeyablePanel`.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App delegate

@MainActor
final class MaintenanceAppDelegate: NSObject, NSApplicationDelegate {

    /// The distributed notification used to reveal the popover when the tool is
    /// re-launched with `--open` while already running.
    private static let showWindowNotification =
        Notification.Name("com.havokentity.mactools.maintenance.showWindow")

    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        setupStatusItem()
        setupShowWindowObserver()

        // If launched with --open, reveal the popover immediately.
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        removeOutsideClickMonitor()
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let icon = NSImage(systemSymbolName: "wrench.and.screwdriver.fill",
                           accessibilityDescription: "Maintenance") ?? NSImage()
        StatusBarButtonContent.install(image: icon, in: item, toolTip: "Maintenance", target: self, action: #selector(statusItemClicked))
    }

    @objc private func statusItemClicked() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: statusItem, action: { [weak self] in
            self?.quit()
        }) {
            return
        }

        togglePanel()
    }

    // MARK: Show-window observer

    private func setupShowWindowObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelFromNotification(_:)),
            name: Self.showWindowNotification,
            object: nil
        )
    }

    @objc private func showPanelFromNotification(_ notification: Notification) {
        showPanel()
    }

    // MARK: Toggle / show / close

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = ensurePanel()
        positionPanel(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeOutsideClickMonitor()
    }

    private func ensurePanel() -> KeyablePanel {
        if let panel { return panel }

        let content = MaintenancePopoverView(onQuit: { [weak self] in
            self?.quit()
        })
        let hosting = NSHostingController(rootView: content)
        hosting.view.layoutSubtreeIfNeeded()

        let size = hosting.view.fittingSize
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        // Round + clip the hosting layer so the panel's shadow follows the rounded
        // .frostedPanel edge instead of casting a square halo (matches the other tools).
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 18
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true

        self.panel = panel
        return panel
    }

    /// Positions the panel directly beneath the menu-bar status item.
    private func positionPanel(_ panel: KeyablePanel) {
        panel.layoutIfNeeded()
        let size = panel.frame.size

        guard let anchorView = statusItem?.button,
              let anchorWindow = anchorView.window,
              let screen = anchorWindow.screen ?? NSScreen.main else {
            // Fallback: top-right of the main screen.
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - size.width - 8
                let y = screen.visibleFrame.maxY - size.height - 8
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            return
        }

        let viewRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorOnScreen = anchorWindow.convertToScreen(viewRectInWindow)

        let visibleFrame = screen.visibleFrame
        var x = anchorOnScreen.midX - size.width / 2
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        let y = max(visibleFrame.minY + 8, anchorOnScreen.minY - size.height - 6)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Outside-click dismissal

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: Quit

    private func quit() {
        closePanel()
        NSApp.terminate(nil)
    }
}
