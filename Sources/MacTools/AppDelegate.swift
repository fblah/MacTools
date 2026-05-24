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
        syncSystemMonitorStatusItem()
        configureToolboxStatusItem()
        configureStatusObservers()
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
        systemMonitorPopover.contentSize = NSSize(width: 440, height: 340)
        systemMonitorPopover.behavior = .transient
        systemMonitorPopover.animates = true
        systemMonitorPopover.contentViewController = NSHostingController(
            rootView: SystemMonitorPopoverView(
                monitor: monitor,
                onQuit: { [weak self] in
                    self?.quit()
                }
            )
        )
    }

    private func configureToolboxStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toolboxStatusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.image = Self.toolboxStatusImage()
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "D'Monte's Toolbox"

    }

    private func configureStatusObservers() {
        snapshotSink = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateSystemMonitorStatusTitle(snapshot)
            }

        defaultsSink = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncSystemMonitorStatusItem()
                self?.keepToolboxAfterMonitor()
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

        let item = NSStatusBar.system.statusItem(withLength: 218)
        systemMonitorStatusItem = item

        let statusView = SystemMonitorStatusView()
        statusView.target = self
        statusView.action = #selector(toggleSystemMonitorPopover(_:))
        item.view = statusView
        systemMonitorStatusView = statusView
        updateSystemMonitorStatusTitle(monitor.snapshot)
    }

    private func keepToolboxAfterMonitor() {
        guard toolboxStatusItem != nil else {
            return
        }

        NSStatusBar.system.removeStatusItem(toolboxStatusItem!)
        toolboxStatusItem = nil
        configureToolboxStatusItem()
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

    @objc private func toggleSystemMonitorPopover(_ sender: Any?) {
        if systemMonitorPopover.isShown {
            closeSystemMonitorPopover()
        } else {
            showSystemMonitorPopover()
        }
    }

    private func showToolboxPopover(from button: NSStatusBarButton) {
        closeSystemMonitorPopover()
        toolboxPopover.show(relativeTo: Self.popoverAnchorRect(for: button.bounds), of: button, preferredEdge: .minY)
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
        systemMonitorPopover.show(relativeTo: Self.popoverAnchorRect(for: statusView.bounds), of: statusView, preferredEdge: .minY)
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
        let width = min(620, max(520, visibleFrame.width * 0.42))
        let height = min(500, max(420, visibleFrame.height - 180))

        return NSSize(width: width, height: height)
    }

    private static func popoverAnchorRect(for bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX, y: bounds.minY - 8, width: bounds.width, height: 1)
    }

    private static func toolboxStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.labelColor.setFill()

            let mark = NSBezierPath()
            mark.windingRule = .evenOdd

            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: rect.midX, y: rect.maxY - 1.6))
            triangle.line(to: NSPoint(x: rect.maxX - 1.4, y: rect.minY + 2.2))
            triangle.line(to: NSPoint(x: rect.minX + 1.4, y: rect.minY + 2.2))
            triangle.close()
            mark.append(triangle)

            let outerD = NSBezierPath()
            outerD.move(to: NSPoint(x: rect.minX + 6.4, y: rect.minY + 6.1))
            outerD.line(to: NSPoint(x: rect.minX + 6.4, y: rect.maxY - 6.1))
            outerD.line(to: NSPoint(x: rect.minX + 8.8, y: rect.maxY - 6.1))
            outerD.curve(
                to: NSPoint(x: rect.minX + 8.8, y: rect.minY + 6.1),
                controlPoint1: NSPoint(x: rect.maxX - 4.7, y: rect.maxY - 6.1),
                controlPoint2: NSPoint(x: rect.maxX - 4.7, y: rect.minY + 6.1)
            )
            outerD.close()
            mark.append(outerD)

            let innerCounter = NSBezierPath()
            innerCounter.move(to: NSPoint(x: rect.minX + 8.0, y: rect.minY + 7.35))
            innerCounter.line(to: NSPoint(x: rect.minX + 8.0, y: rect.maxY - 7.35))
            innerCounter.line(to: NSPoint(x: rect.minX + 8.8, y: rect.maxY - 7.35))
            innerCounter.curve(
                to: NSPoint(x: rect.minX + 8.8, y: rect.minY + 7.35),
                controlPoint1: NSPoint(x: rect.maxX - 6.15, y: rect.maxY - 7.35),
                controlPoint2: NSPoint(x: rect.maxX - 6.15, y: rect.minY + 7.35)
            )
            innerCounter.close()
            mark.append(innerCounter)

            mark.fill()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "D'Monte's Toolbox"

        return image
    }
}
