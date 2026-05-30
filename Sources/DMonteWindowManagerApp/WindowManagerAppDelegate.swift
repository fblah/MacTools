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

/// The menu-bar tray button for Window Manager.
private final class WindowManagerStatusView: NSControl {
    static let statusWidth: CGFloat = 22

    var onClick: (() -> Void)?

    private let image: NSImage
    private let highlightLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    init() {
        image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Manager") ?? NSImage()
        super.init(frame: NSRect(x: 0, y: 0, width: Self.statusWidth, height: NSStatusBar.system.thickness))
        wantsLayer = true
        image.isTemplate = true
        highlightLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.11).cgColor
        highlightLayer.cornerRadius = 6
        highlightLayer.cornerCurve = .continuous
        highlightLayer.masksToBounds = true
        highlightLayer.isHidden = true
        layer?.insertSublayer(highlightLayer, at: 0)
        toolTip = "Window Manager"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let glyphSize = NSSize(width: 16, height: 16)
        let glyphRect = NSRect(
            x: bounds.midX - glyphSize.width / 2,
            y: bounds.midY - glyphSize.height / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
        NSColor.labelColor.set()
        image.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds.insetBy(dx: 1, dy: 3)
    }

    override func mouseDown(with event: NSEvent) {
        highlightLayer.isHidden = false
        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        highlightLayer.isHidden = !isMouseInside
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { highlightLayer.isHidden = false }
    override func mouseExited(with event: NSEvent) { highlightLayer.isHidden = true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    private var isMouseInside: Bool {
        guard let window else { return false }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = convert(mouseInWindow, from: nil)
        return bounds.contains(mouseInView)
    }
}

@MainActor
final class WindowManagerAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = WindowManagerController()

    private var statusItem: NSStatusItem?
    private weak var statusView: WindowManagerStatusView?
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
            self.statusView = nil
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
        let item = NSStatusBar.system.statusItem(withLength: WindowManagerStatusView.statusWidth)
        statusItem = item

        let statusView = WindowManagerStatusView()
        statusView.onClick = { [weak self] in
            self?.togglePanel()
        }
        StatusBarButtonContent.install(statusView, in: item)
        self.statusView = statusView
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
        guard let statusView, let window = statusView.window, let screen = window.screen ?? NSScreen.main else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let viewFrameInWindow = statusView.convert(statusView.bounds, to: nil)
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
