import AppKit
import Combine
import DMonteCore
import SwiftUI

/// Distributed notification used to reveal this helper's popover when the Toolbox (or a second
/// launch with `--open`) asks for it.
enum WindowManagerNotifications {
    static let showWindow = Notification.Name("com.havokentity.mactools.windowmanager.showWindow")
}

/// A panel that can take keyboard focus while floating over other apps. Mirrors the other tools'
/// floating-panel behaviour and dismissal handling.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WindowManagerAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = WindowManagerController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        // Register snap shortcuts up front if we already have Accessibility; otherwise the
        // controller registers them automatically the moment the grant is detected.
        if controller.hasAccessibility {
            controller.registerHotKeys()
        }

        configurePanel()
        configureStatusItem()
        configureShowNotification()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        removeClickMonitor()
        panel?.orderOut(nil)
        panel = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        let size = WindowManagerSizing.preferredSize()
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingController(
            rootView: WindowManagerPopoverView(controller: controller, onQuit: { [weak self] in self?.quit() })
        )
        hosting.view.frame = NSRect(origin: .zero, size: size)
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 18
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true
        panel.contentViewController = hosting
        panel.setContentSize(size)
        self.panel = panel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let icon = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Manager") ?? NSImage()
        StatusBarButtonContent.install(image: icon, in: item, toolTip: "Window Manager", target: self, action: #selector(statusItemClicked))
    }

    @objc private func statusItemClicked() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: statusItem, action: { [weak self] in
            self?.quit()
        }) {
            return
        }

        togglePanel()
    }

    private func configureShowNotification() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelFromNotification(_:)),
            name: WindowManagerNotifications.showWindow,
            object: nil
        )
    }

    @objc private func showPanelFromNotification(_ notification: Notification) {
        showPanel()
    }

    // MARK: - Panel show/hide

    private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }

        // The grant may have changed since launch; refresh so the banner/tiles reflect reality.
        controller.refreshPermission()

        let size = WindowManagerSizing.preferredSize()
        panel.setContentSize(size)
        panel.setFrame(panelFrame(for: size), display: true)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        startClickMonitorAfterOpeningClick()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeClickMonitor()
    }

    private func panelFrame(for size: NSSize) -> NSRect {
        guard let statusButton = statusItem?.button, let window = statusButton.window, let screen = window.screen ?? NSScreen.main else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let viewFrameInWindow = statusButton.convert(statusButton.bounds, to: nil)
        let anchorFrame = window.convertToScreen(viewFrameInWindow)
        let visibleFrame = screen.visibleFrame
        let x = min(
            max(anchorFrame.midX - size.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        let y = max(visibleFrame.minY + 8, anchorFrame.minY - size.height - 8)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Event monitors

    private func startClickMonitorAfterOpeningClick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.startClickMonitor()
        }
    }

    private func startClickMonitor() {
        guard panel?.isVisible == true, clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func quit() {
        closePanel()
        NSApp.terminate(nil)
    }
}
