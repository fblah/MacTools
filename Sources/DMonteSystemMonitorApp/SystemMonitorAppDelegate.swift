import AppKit
import Combine
import DMonteCore
import SwiftUI

@MainActor
final class SystemMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private var statusItem: NSStatusItem?
    private var statusView: SystemMonitorStatusView?
    private var panel: NSPanel?
    private var snapshotSink: AnyCancellable?
    private var defaultsSink: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        configurePopover()
        configureStatusItem()
        configureObservers()
        configureEnvironmentObservers()
        SystemMonitorLoginItem.refreshIfEnabled()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        snapshotSink = nil
        defaultsSink = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        panel?.orderOut(nil)

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            self.statusView = nil
        }
    }

    private func configurePopover() {
        let panelSize = SystemMonitorPanelSizing.preferredSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let hostingController = NSHostingController(
            rootView: SystemMonitorPopoverView(
                monitor: monitor,
                onQuit: { [weak self] in
                    self?.quitSystemMonitor()
                }
            )
        )
        hostingController.view.frame = NSRect(origin: .zero, size: panelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 18
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        panel.contentViewController = hostingController
        panel.contentMinSize = panelSize
        panel.contentMaxSize = panelSize
        panel.setContentSize(panelSize)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.level = .popUpMenu
        self.panel = panel
    }

    private func configureStatusItem() {
        let showsIcon = AppDefaults.shared.bool(forKey: DefaultsKey.systemMonitorShowsTrayIcon)
        // A concrete (non-variable) length keeps AppKit from treating the button as empty and
        // culling it when the menu bar gets crowded — the disappearing-icon bug that drove the
        // migration off the old custom-subview install path for the other 17 tools.
        let item = NSStatusBar.system.statusItem(withLength: SystemMonitorStatusView.statusWidth(showsIcon: showsIcon))
        statusItem = item

        // System Monitor is the hard case: the tray content is a live multi-metric strip, not a
        // single icon/title. Keep the rich custom view, but host it inside the status item's own
        // button (the AppKit-managed content the menu bar won't drop) and let the button's
        // target/action handle the click instead of the view's onClick closure.
        let statusView = SystemMonitorStatusView()
        statusView.applyShowsIcon(showsIcon)
        self.statusView = statusView

        if let button = item.button {
            button.toolTip = "System Monitor"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            statusView.frame = button.bounds
            statusView.autoresizingMask = [.width, .height]
            button.addSubview(statusView)
        }

        updateStatusTitle(monitor.snapshot)
    }

    @objc private func statusItemClicked() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: statusItem, action: { [weak self] in
            self?.quitSystemMonitor()
        }) {
            return
        }

        togglePopover()
    }

    private func configureObservers() {
        snapshotSink = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusTitle(snapshot)
            }

        defaultsSink = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: AppDefaults.shared
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            let showsIcon = AppDefaults.shared.bool(forKey: DefaultsKey.systemMonitorShowsTrayIcon)
            self?.statusView?.applyShowsIcon(showsIcon)
            self?.statusItem?.length = SystemMonitorStatusView.statusWidth(showsIcon: showsIcon)
        }
    }

    private func configureEnvironmentObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverForEnvironmentChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(closePopoverForEnvironmentChange(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(closePopoverForEnvironmentChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func closePopoverForEnvironmentChange(_ notification: Notification) {
        closePopover()
    }

    private func updateStatusTitle(_ snapshot: MetricSnapshot) {
        statusView?.update(snapshot: snapshot)
    }

    private func togglePopover() {
        if let panel, panel.isVisible {
            guard Self.panelIsOnVisibleScreen(panel) else {
                closePopover()
                showPopover()
                return
            }

            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let statusView, let panel else {
            return
        }

        let panelSize = SystemMonitorPanelSizing.preferredSize()
        panel.contentMinSize = panelSize
        panel.contentMaxSize = panelSize
        panel.setContentSize(panelSize)
        panel.setFrame(Self.panelFrame(for: panelSize, anchoredTo: statusView), display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: false)
        startOutsideClickMonitorAfterOpeningClick()
    }

    private func closePopover() {
        panel?.orderOut(nil)
        stopOutsideClickMonitorIfIdle()
    }

    private func startOutsideClickMonitor() {
        guard panel?.isVisible == true else {
            return
        }

        if eventMonitor != nil {
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func startOutsideClickMonitorAfterOpeningClick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.startOutsideClickMonitor()
        }
    }

    private func stopOutsideClickMonitorIfIdle() {
        guard panel?.isVisible != true, let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private static func panelIsOnVisibleScreen(_ panel: NSPanel) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(panel.frame)
        }
    }

    private func quitSystemMonitor() {
        NSApp.terminate(nil)
    }

    private static func panelFrame(for size: NSSize, anchoredTo view: NSView) -> NSRect {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else {
            return centeredPanelFrame(for: size)
        }

        let viewFrameInWindow = view.convert(view.bounds, to: nil)
        let anchorFrame = window.convertToScreen(viewFrameInWindow)
        let visibleFrame = screen.visibleFrame
        let x = min(
            max(anchorFrame.midX - (size.width / 2), visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        let y = max(visibleFrame.minY + 8, anchorFrame.minY - size.height - 8)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func centeredPanelFrame(for size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
