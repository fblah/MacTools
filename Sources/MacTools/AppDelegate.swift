import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let toolboxPopover = NSPopover()
    private let systemMonitorPopover = NSPopover()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var toolboxStatusItem: NSStatusItem?
    private var systemMonitorStatusItem: NSStatusItem?
    private var systemMonitorStatusView: SystemMonitorStatusView?
    private var snapshotSink: AnyCancellable?
    private var defaultsSink: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.systemMonitorEnabled: true
        ])

        configureToolboxPopover()
        configureSystemMonitorPopover()
        configureToolboxStatusItem()
        syncSystemMonitorStatusItem()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func configureToolboxPopover() {
        let popoverSize = Self.preferredPopoverSize()
        let rootView = ToolPopoverView(
            monitor: monitor,
            popoverSize: popoverSize,
            onOpenSystemMonitor: { [weak self] in
                self?.openSystemMonitorFromToolbox()
            },
            onCheckForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )

        toolboxPopover.contentSize = popoverSize
        toolboxPopover.behavior = .transient
        toolboxPopover.animates = true
        toolboxPopover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func configureSystemMonitorPopover() {
        systemMonitorPopover.contentSize = NSSize(width: 520, height: 430)
        systemMonitorPopover.behavior = .transient
        systemMonitorPopover.animates = true
        systemMonitorPopover.contentViewController = NSHostingController(
            rootView: SystemMonitorPopoverView(
                monitor: monitor,
                onSettings: { [weak self] in
                    self?.showToolboxFromSystemMonitor()
                }
            )
        )
    }

    private func configureToolboxStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toolboxStatusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "D'Monte's Toolbox")
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.title = " Toolbox"

        snapshotSink = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateSystemMonitorStatusTitle(snapshot)
            }

        defaultsSink = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSystemMonitorStatusItem()
            }
    }

    private func syncSystemMonitorStatusItem() {
        let isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.systemMonitorEnabled)

        if isEnabled {
            configureSystemMonitorStatusItemIfNeeded()
        } else {
            closeSystemMonitorPopover()

        if let systemMonitorStatusItem {
            NSStatusBar.system.removeStatusItem(systemMonitorStatusItem)
            self.systemMonitorStatusItem = nil
            self.systemMonitorStatusView = nil
        }
        }
    }

    private func configureSystemMonitorStatusItemIfNeeded() {
        guard systemMonitorStatusItem == nil else {
            updateSystemMonitorStatusTitle(monitor.snapshot)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: 270)
        systemMonitorStatusItem = item

        let statusView = SystemMonitorStatusView()
        statusView.onClick = { [weak self] in
            self?.toggleSystemMonitorPopover()
        }
        item.view = statusView
        systemMonitorStatusView = statusView
        updateSystemMonitorStatusTitle(monitor.snapshot)
    }

    private func updateSystemMonitorStatusTitle(_ snapshot: MetricSnapshot) {
        systemMonitorStatusView?.update(snapshot: snapshot)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if toolboxPopover.isShown {
            closeToolboxPopover()
        } else {
            showToolboxPopover(from: sender)
        }
    }

    private func toggleSystemMonitorPopover() {
        if systemMonitorPopover.isShown {
            closeSystemMonitorPopover()
        } else {
            showSystemMonitorPopover()
        }
    }

    private func showToolboxPopover(from button: NSStatusBarButton) {
        closeSystemMonitorPopover()
        toolboxPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        toolboxPopover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()
    }

    private func closeToolboxPopover() {
        toolboxPopover.performClose(nil)
        stopOutsideClickMonitorIfIdle()
    }

    private func showSystemMonitorPopover() {
        guard let statusView = systemMonitorStatusView else {
            return
        }

        closeToolboxPopover()
        systemMonitorPopover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
        systemMonitorPopover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()
    }

    private func closeSystemMonitorPopover() {
        systemMonitorPopover.performClose(nil)
        stopOutsideClickMonitorIfIdle()
    }

    private func openSystemMonitorFromToolbox() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.systemMonitorEnabled) else {
            return
        }

        syncSystemMonitorStatusItem()
        closeToolboxPopover()

        showSystemMonitorPopover()
    }

    private func showToolboxFromSystemMonitor() {
        closeSystemMonitorPopover()

        if let button = toolboxStatusItem?.button {
            showToolboxPopover(from: button)
        }
    }

    private func startOutsideClickMonitor() {
        if eventMonitor != nil {
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeToolboxPopover()
            self?.closeSystemMonitorPopover()
        }
    }

    private func stopOutsideClickMonitorIfIdle() {
        guard !toolboxPopover.isShown, !systemMonitorPopover.isShown, let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    private static func preferredPopoverSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(760, max(600, visibleFrame.width * 0.52))
        let height = min(620, max(500, visibleFrame.height - 120))

        return NSSize(width: width, height: height)
    }

}
