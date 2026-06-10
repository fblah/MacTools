import AppKit
import Combine
import DMonteCore
import SwiftUI

/// Distributed notification used to reveal this helper's popover when the Toolbox (or a second
/// launch with `--open`) asks for it.
enum KeepAwakeNotifications {
    static let showWindow = Notification.Name("com.havokentity.mactools.keepawake.showWindow")
}

@MainActor
final class KeepAwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = KeepAwakeController()

    private var statusItem: HelperStatusItem?
    private var panelHost: HelperPanelHost?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperPanelHost(
            configuration: HelperPanelHost.Configuration(
                sizing: .preferred({ KeepAwakeSizing.preferredSize() })
            ),
            content: .viewController({ [controller, weak self] in
                NSHostingController(
                    rootView: KeepAwakePopoverView(controller: controller, onQuit: { self?.quit() })
                )
            }),
            anchorView: { [weak self] in self?.statusItem?.button }
        )
        panelHost = host
        host.configure()

        statusItem = HelperStatusItem(
            image: Self.statusIcon(awake: false),
            toolTip: "Keep Awake",
            primaryAction: { [weak self] in self?.panelHost?.toggle() },
            quitAction: { [weak self] in self?.quit() }
        )

        // Reflect the controller's current state immediately (e.g. relaunch while already awake).
        updateStatusIcon()

        host.observeShowNotification(named: KeepAwakeNotifications.showWindow)
        observeControllerState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelHost?.stopObservingShowNotifications()
        panelHost?.removeOutsideClickMonitor()
        cancellables.removeAll()
        controller.deactivate()
        panelHost?.dismissForTermination()
        statusItem?.remove()
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

    /// Keep the tray glyph in sync with the controller's active state.
    private func observeControllerState() {
        controller.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func quit() {
        panelHost?.close()
        NSApp.terminate(nil)
    }
}
