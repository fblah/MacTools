import AppKit
import Combine
import DMonteCore
import SwiftUI

/// Distributed notification used to reveal this helper's popover when the Toolbox (or a second
/// launch with `--open`) asks for it.
enum KeepAwakeNotifications {
    static let showWindow = Notification.Name("com.havokentity.mactools.keepawake.showWindow")
}

/// A panel that can take keyboard focus while still floating over other apps. Keep Awake does not
/// need keyboard input, but mirroring the Clipboard pattern keeps the floating-panel behaviour and
/// dismissal handling identical across tools.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class KeepAwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = KeepAwakeController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        configurePanel()
        configureStatusItem()
        configureShowNotification()
        observeControllerState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        removeClickMonitor()
        cancellables.removeAll()
        controller.deactivate()
        panel?.orderOut(nil)
        panel = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        let size = KeepAwakeSizing.preferredSize()
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
            rootView: KeepAwakePopoverView(controller: controller, onQuit: { [weak self] in self?.quit() })
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

        StatusBarButtonContent.install(
            image: Self.statusIcon(awake: false),
            in: item,
            toolTip: "Keep Awake",
            target: self,
            action: #selector(statusItemClicked)
        )

        // Reflect the controller's current state immediately (e.g. relaunch while already awake).
        updateStatusIcon()
    }

    @objc private func statusItemClicked() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: statusItem, action: { [weak self] in
            self?.quit()
        }) {
            return
        }

        togglePanel()
    }

    /// The two-state tray glyph: a filled cup when awake, an outline cup when idle. Forced to
    /// template so AppKit tints it adaptive white and gives it the native rollover highlight.
    private static func statusIcon(awake: Bool) -> NSImage {
        let name = awake ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Keep Awake") ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// Swaps the status button's image to match the controller's active state. Driven by the
    /// `$isActive` Combine sink so the tray glyph stays in sync with awake/idle transitions.
    private func updateStatusIcon() {
        statusItem?.button?.image = Self.statusIcon(awake: controller.isActive)
    }

    private func configureShowNotification() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelFromNotification(_:)),
            name: KeepAwakeNotifications.showWindow,
            object: nil
        )
    }

    /// Keep the tray glyph in sync with the controller's active state.
    private func observeControllerState() {
        controller.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
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

        let size = KeepAwakeSizing.preferredSize()
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
