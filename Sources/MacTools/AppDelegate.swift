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
        UserDefaults.standard.register(defaults: [
            DefaultsKey.systemMonitorEnabled: true
        ])

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
        let popoverSize = Self.preferredPopoverSize()
        let rootView = ToolPopoverView(
            monitor: monitor,
            popoverSize: popoverSize,
            onCheckForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )

        popover.contentSize = popoverSize
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
        button.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "D'Monte's Toolbox")
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        button.attributedTitle = Self.statusTitle("  starting...\n")

        snapshotSink = monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak button] snapshot in
                if UserDefaults.standard.bool(forKey: DefaultsKey.systemMonitorEnabled) {
                    button?.attributedTitle = Self.statusTitle(snapshot.menuBarTitle)
                } else {
                    button?.attributedTitle = Self.statusTitle("D'Monte's\nToolbox")
                }
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

    private static func preferredPopoverSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(760, max(600, visibleFrame.width * 0.52))
        let height = min(620, max(500, visibleFrame.height - 120))

        return NSSize(width: width, height: height)
    }

    private static func statusTitle(_ title: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = -2

        return NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
