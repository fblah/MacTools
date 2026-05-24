import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let popover = NSPopover()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var statusItem: NSStatusItem?
    private var snapshotSink: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func configurePopover() {
        let rootView = ToolPopoverView(
            monitor: monitor,
            onCheckForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )

        popover.contentSize = NSSize(width: 540, height: 560)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MacTools")
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = "  starting..."

        snapshotSink = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak button] snapshot in
                button?.title = snapshot.menuBarTitle
            }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func startOutsideClickMonitor() {
        if eventMonitor != nil {
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
