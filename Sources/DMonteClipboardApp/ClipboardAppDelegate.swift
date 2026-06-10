import AppKit
import DMonteCore
import SwiftUI

/// A panel that can take keyboard focus (so the user can type to search and navigate) while
/// still floating over other apps. We re-activate the previous app before pasting.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ClipboardAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ClipboardController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private weak var lastActiveApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        ClipboardLoginItem.refreshIfEnabled()

        controller.onRequestClose = { [weak self] in
            self?.closePanel()
        }
        controller.startCapturing()

        configurePanel()
        configureStatusItem()
        configureShowNotification()
        observeActiveApp()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeClickMonitor()
        removeKeyMonitor()
        hotKey = nil
        panel?.orderOut(nil)
        panel = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        let size = ClipboardSizing.preferredSize()
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
            rootView: ClipboardPopoverView(controller: controller, onQuit: { [weak self] in self?.quit() })
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

        let icon = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Clipboard") ?? NSImage()
        StatusBarButtonContent.install(image: icon, in: item, toolTip: "Clipboard", target: self, action: #selector(statusItemClicked))
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
            name: HelperNotifications.showClipboardWindow,
            object: nil
        )
    }

    private func observeActiveApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func registerHotKey() {
        hotKey = GlobalHotKey.commandShiftV { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
    }

    @objc private func showPanelFromNotification(_ notification: Notification) {
        showPanel()
    }

    @objc private func activeAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != ClipboardMonitor.bundleIdentifier else {
            return
        }
        lastActiveApp = app
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

        // The app to paste into is whatever was frontmost just before we appeared.
        controller.pasteTarget = lastActiveApp ?? NSWorkspace.shared.frontmostApplication
        controller.prepareForShow()

        let size = ClipboardSizing.preferredSize()
        panel.setContentSize(size)
        panel.setFrame(panelFrame(for: size), display: true)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installKeyMonitor()
        startClickMonitorAfterOpeningClick()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeClickMonitor()
        removeKeyMonitor()
    }

    private func panelFrame(for size: NSSize) -> NSRect {
        guard let button = statusItem?.button, let window = button.window, let screen = window.screen ?? NSScreen.main else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let viewFrameInWindow = button.convert(button.bounds, to: nil)
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

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.controller.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

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
