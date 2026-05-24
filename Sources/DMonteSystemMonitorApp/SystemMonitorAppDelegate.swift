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

        guard AppDefaults.shared.bool(forKey: DefaultsKey.systemMonitorEnabled) else {
            NSApp.terminate(nil)
            return
        }

        configurePopover()
        configureStatusItem()
        configureObservers()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
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
        let item = NSStatusBar.system.statusItem(withLength: SystemMonitorStatusView.statusWidth)
        statusItem = item

        let statusView = SystemMonitorStatusView()
        statusView.onClick = { [weak self] in
            self?.togglePopover()
        }
        item.view = statusView
        self.statusView = statusView
        updateStatusTitle(monitor.snapshot)
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
        .sink { _ in
            if !AppDefaults.shared.bool(forKey: DefaultsKey.systemMonitorEnabled) {
                NSApp.terminate(nil)
            }
        }
    }

    private func updateStatusTitle(_ snapshot: MetricSnapshot) {
        statusView?.update(snapshot: snapshot)
    }

    private func togglePopover() {
        if panel?.isVisible == true {
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

    private func quitSystemMonitor() {
        AppDefaults.shared.set(false, forKey: DefaultsKey.systemMonitorEnabled)
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
