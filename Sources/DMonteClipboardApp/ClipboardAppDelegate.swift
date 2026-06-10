import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class ClipboardAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ClipboardController()

    private var statusItem: HelperStatusItem?
    private var panelHost: HelperPanelHost?
    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?
    private weak var lastActiveApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        ClipboardLoginItem.refreshIfEnabled()

        controller.onRequestClose = { [weak self] in
            self?.panelHost?.close()
        }
        controller.startCapturing()

        configurePanelHost()
        configureStatusItem()
        panelHost?.observeShowNotification(named: HelperNotifications.showClipboardWindow)
        observeActiveApp()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelHost?.stopObservingShowNotifications()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panelHost?.removeOutsideClickMonitor()
        removeKeyMonitor()
        hotKey = nil
        panelHost?.dismissForTermination()
        statusItem?.remove()
    }

    // MARK: - Setup

    private func configurePanelHost() {
        // The panel can take keyboard focus (so the user can type to search and navigate) while
        // still floating over other apps. We re-activate the previous app before pasting.
        let host = HelperPanelHost(
            configuration: HelperPanelHost.Configuration(
                sizing: .preferred({ ClipboardSizing.preferredSize() })
            ),
            content: .viewController({ [controller, weak self] in
                NSHostingController(
                    rootView: ClipboardPopoverView(controller: controller, onQuit: { self?.quit() })
                )
            }),
            anchorView: { [weak self] in self?.statusItem?.button }
        )
        host.onWillShow = { [weak self] in
            guard let self else { return }
            // The app to paste into is whatever was frontmost just before we appeared.
            self.controller.pasteTarget = self.lastActiveApp ?? NSWorkspace.shared.frontmostApplication
            self.controller.prepareForShow()
        }
        host.onDidShow = { [weak self] in
            self?.installKeyMonitor()
        }
        host.onDidClose = { [weak self] in
            self?.removeKeyMonitor()
        }
        panelHost = host
        host.configure()
    }

    private func configureStatusItem() {
        let icon = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "Clipboard") ?? NSImage()
        statusItem = HelperStatusItem(
            image: icon,
            toolTip: "Clipboard",
            primaryAction: { [weak self] in self?.panelHost?.toggle() },
            quitAction: { [weak self] in self?.quit() }
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
        // Release the old key before creating its replacement: GlobalHotKey refuses
        // duplicate ids, and plain reassignment constructs the new key while the old
        // one is still registered.
        hotKey = nil
        hotKey = GlobalHotKey.commandShiftV { [weak self] in
            Task { @MainActor in
                self?.panelHost?.toggle()
            }
        }
    }

    @objc private func activeAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != ClipboardMonitor.bundleIdentifier else {
            return
        }
        lastActiveApp = app
    }

    // MARK: - Key monitor

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

    private func quit() {
        panelHost?.close()
        NSApp.terminate(nil)
    }
}
