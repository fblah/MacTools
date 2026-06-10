import AppKit
import DMonteCore
import SwiftUI

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
final class UninstallerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var hasPositionedWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        configureWindow()
        configureWindowShowNotifications()

        DispatchQueue.main.async { [weak self] in
            self?.showWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)

        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }

    private func configureWindow() {
        let windowSize = UninstallerSizing.windowSize
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingController = NSHostingController(
            rootView: UninstallerPopoverView(
                onQuit: { [weak self] in
                    self?.quitUninstaller()
                }
            )
        )
        hostingController.view.frame = NSRect(origin: .zero, size: windowSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 18
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        window.contentViewController = hostingController
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize
        window.setContentSize(windowSize)
        window.delegate = self
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.level = .normal
        window.title = "Uninstall Apps"
        self.window = window
    }

    private func configureWindowShowNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showWindowFromNotification(_:)),
            name: HelperNotifications.showUninstallerWindow,
            object: nil
        )
    }

    @objc private func showWindowFromNotification(_ notification: Notification) {
        showWindow()
    }

    private func showWindow() {
        guard let window else {
            return
        }

        let windowSize = UninstallerSizing.windowSize
        window.contentMinSize = windowSize
        window.contentMaxSize = windowSize

        if hasPositionedWindow {
            window.setContentSize(windowSize)
        } else {
            window.setFrame(Self.centeredWindowFrame(for: windowSize), display: true)
            hasPositionedWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func quitUninstaller() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private static func centeredWindowFrame(for size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
