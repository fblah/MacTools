import AppKit
import Combine
import DMonteCore
import SwiftUI

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DiskAnalyzerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var hasPositionedWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        configureWindow()
        configureWindowShowNotifications()

        if CommandLine.arguments.contains("--open") || statusItem == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)

        window?.orderOut(nil)
        window?.delegate = nil
        window = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private static let minimumContentSize = NSSize(width: 520, height: 460)
    private static let windowedCornerRadius: CGFloat = 18

    private func configureWindow() {
        let windowSize = DiskAnalyzerSizing.preferredSize()
        // Titled + full-size content keeps the frosted, chrome-less look while
        // allowing the user to resize the window and enter native full screen.
        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let hostingController = NSHostingController(
            rootView: DiskAnalyzerWindowView(
                onQuit: { [weak self] in
                    self?.quitDiskAnalyzer()
                }
            )
        )
        hostingController.view.autoresizingMask = [.width, .height]
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = Self.windowedCornerRadius
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        window.contentViewController = hostingController
        window.contentMinSize = Self.minimumContentSize
        window.setContentSize(windowSize)
        window.delegate = self
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.level = .normal
        window.title = "Disk Usage Analyzer"
        self.window = window
    }

    // Drop the rounded corners in full screen (where the content fills the whole
    // display) and restore them when returning to a windowed frame.
    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.contentViewController?.view.layer?.cornerRadius = 0
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.contentViewController?.view.layer?.cornerRadius = Self.windowedCornerRadius
    }

    private func configureWindowShowNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showWindowFromNotification(_:)),
            name: HelperNotifications.showDiskAnalyzerWindow,
            object: nil
        )
    }

    @objc private func showWindowFromNotification(_ notification: Notification) {
        showWindow()
    }

    private func showWindow(relativeTo view: NSView? = nil) {
        guard let window else {
            return
        }

        // Only size/position on first show; afterwards preserve whatever size the
        // user has dragged the window to (or full screen).
        if !hasPositionedWindow {
            let windowSize = DiskAnalyzerSizing.preferredSize()
            let frame = if let view {
                Self.windowFrame(for: windowSize, near: view)
            } else {
                Self.centeredWindowFrame(for: windowSize)
            }
            window.setFrame(frame, display: true)
            hasPositionedWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func quitDiskAnalyzer() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if statusItem == nil {
            NSApp.terminate(nil)
        }
    }

    private static func windowFrame(for size: NSSize, near view: NSView) -> NSRect {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else {
            return centeredWindowFrame(for: size)
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
