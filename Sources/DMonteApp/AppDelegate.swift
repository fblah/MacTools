import AppKit
import Combine
import DMonteCore
import Darwin
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let systemMonitorHelperBundleIdentifier = "com.havokentity.mactools.systemmonitor"
    private static let uninstallerHelperBundleIdentifier = "com.havokentity.mactools.uninstaller"
    private static let cleanDriveHelperBundleIdentifier = "com.havokentity.mactools.cleandrive"
    private static let videoDownloaderHelperBundleIdentifier = "com.havokentity.mactools.videodownloader"

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var toolboxStatusItem: NSStatusItem?
    private weak var toolboxStatusView: ToolboxStatusView?
    private var toolboxPanel: NSPanel?
    private var defaultsSink: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        configureToolboxPopover()
        configureToolboxStatusItem()
        configureToolboxShowNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        defaultsSink = nil

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        toolboxPanel?.orderOut(nil)
        toolboxPanel = nil

        if let toolboxStatusItem {
            NSStatusBar.system.removeStatusItem(toolboxStatusItem)
            self.toolboxStatusItem = nil
            self.toolboxStatusView = nil
        }
    }

    private func configureToolboxPopover() {
        let popoverSize = Self.preferredPopoverSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: popoverSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingController = NSHostingController(rootView: toolboxRootView(popoverSize: popoverSize))
        hostingController.view.frame = NSRect(origin: .zero, size: popoverSize)
        panel.contentViewController = hostingController
        panel.contentMinSize = popoverSize
        panel.contentMaxSize = popoverSize
        panel.setContentSize(popoverSize)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.level = .popUpMenu
        toolboxPanel = panel
    }

    private func configureToolboxStatusItem() {
        guard toolboxStatusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: ToolboxStatusView.statusWidth)
        toolboxStatusItem = item

        let statusView = ToolboxStatusView(image: Self.toolboxStatusImage())
        statusView.onClick = { [weak self, weak statusView] in
            guard let statusView else {
                return
            }

            self?.toggleToolboxPopover(from: statusView)
        }
        item.view = statusView
        toolboxStatusView = statusView
    }

    private func toolboxRootView(popoverSize: NSSize) -> some View {
        ToolPopoverView(
            popoverSize: popoverSize,
            onOpenSystemMonitor: { [weak self] in
                self?.openSystemMonitorFromToolbox()
            },
            onOpenUninstaller: { [weak self] in
                self?.openUninstallerFromToolbox()
            },
            onOpenCleanDrive: { [weak self] in
                self?.openCleanDriveFromToolbox()
            },
            onOpenVideoDownloader: { [weak self] in
                self?.openVideoDownloaderFromToolbox()
            },
            onCheckForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onQuit: { [weak self] in
                self?.quit()
            }
        )
    }

    private func configureToolboxShowNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showToolboxFromNotification(_:)),
            name: HelperNotifications.showToolboxWindow,
            object: nil
        )
    }

    @objc private func showToolboxFromNotification(_ notification: Notification) {
        guard let statusView = toolboxStatusView else {
            return
        }

        showToolboxPopover(from: statusView)
    }

    private func launchHelper(
        bundleIdentifier: String,
        appName: String,
        executableName: String,
        arguments: [String] = []
    ) {
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        guard runningApplications.isEmpty else {
            if arguments.contains("--open") {
                if bundleIdentifier == Self.systemMonitorHelperBundleIdentifier {
                    DistributedNotificationCenter.default().postNotificationName(
                        HelperNotifications.showSystemMonitorWindow,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                } else if bundleIdentifier == Self.uninstallerHelperBundleIdentifier {
                    DistributedNotificationCenter.default().postNotificationName(
                        HelperNotifications.showUninstallerWindow,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                } else if bundleIdentifier == Self.cleanDriveHelperBundleIdentifier {
                    DistributedNotificationCenter.default().postNotificationName(
                        HelperNotifications.showCleanDriveWindow,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                } else if bundleIdentifier == Self.videoDownloaderHelperBundleIdentifier {
                    DistributedNotificationCenter.default().postNotificationName(
                        HelperNotifications.showVideoDownloaderWindow,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
            }

            return
        }

        if let helperAppURL = bundledHelperURL(appName: appName), FileManager.default.fileExists(atPath: helperAppURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.arguments = arguments
            NSWorkspace.shared.openApplication(at: helperAppURL, configuration: configuration)
            return
        }

        if let helperExecutableURL = debugHelperExecutableURL(executableName: executableName),
           FileManager.default.fileExists(atPath: helperExecutableURL.path) {
            _ = try? Process.run(helperExecutableURL, arguments: arguments)
        }
    }

    private func terminateHelper(bundleIdentifier: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach { $0.terminate() }
    }

    private func bundledHelperURL(appName: String) -> URL? {
        Bundle.main.bundleURL.appendingPathComponent("Contents").appendingPathComponent("Helpers").appendingPathComponent(appName)
    }

    private func debugHelperExecutableURL(executableName: String) -> URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(executableName)
    }

    private func toggleToolboxPopover(from view: NSView) {
        if isToolboxPanelVisible {
            closeToolboxPopover()
        } else {
            showToolboxPopover(from: view)
        }
    }

    private func showToolboxPopover(from view: NSView) {
        guard let panel = toolboxPanel else {
            return
        }

        let size = Self.preferredPopoverSize()
        panel.setContentSize(size)
        panel.setFrame(Self.panelFrame(for: size, anchoredTo: view), display: true)
        panel.orderFrontRegardless()
        startOutsideClickMonitorAfterOpeningClick()
    }

    private func closeToolboxPopover() {
        toolboxPanel?.orderOut(nil)
        stopOutsideClickMonitorIfIdle()
    }

    private func openSystemMonitorFromToolbox() {
        launchHelper(
            bundleIdentifier: Self.systemMonitorHelperBundleIdentifier,
            appName: "DMonte System Monitor.app",
            executableName: "DMonteSystemMonitor"
        )
        closeToolboxPopover()
    }

    private func openUninstallerFromToolbox() {
        launchHelper(
            bundleIdentifier: Self.uninstallerHelperBundleIdentifier,
            appName: "DMonte Uninstaller.app",
            executableName: "DMonteUninstaller",
            arguments: ["--open"]
        )
        closeToolboxPopover()
    }

    private func openCleanDriveFromToolbox() {
        launchHelper(
            bundleIdentifier: Self.cleanDriveHelperBundleIdentifier,
            appName: "DMonte Clean Drive.app",
            executableName: "DMonteCleanDrive",
            arguments: ["--open"]
        )
        closeToolboxPopover()
    }

    private func openVideoDownloaderFromToolbox() {
        launchHelper(
            bundleIdentifier: Self.videoDownloaderHelperBundleIdentifier,
            appName: "DMonte Video Downloader.app",
            executableName: "DMonteVideoDownloader",
            arguments: ["--open"]
        )
        closeToolboxPopover()
    }

    private func startOutsideClickMonitor() {
        guard isToolboxPanelVisible else {
            return
        }

        if eventMonitor != nil {
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeToolboxPopover()
        }
    }

    private func startOutsideClickMonitorAfterOpeningClick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.startOutsideClickMonitor()
        }
    }

    private func stopOutsideClickMonitorIfIdle() {
        guard !isToolboxPanelVisible, let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private var isToolboxPanelVisible: Bool {
        toolboxPanel?.isVisible == true
    }

    private func quit() {
        closeToolboxPopover()

        if let toolboxStatusItem {
            NSStatusBar.system.removeStatusItem(toolboxStatusItem)
            self.toolboxStatusItem = nil
            self.toolboxStatusView = nil
        }

        NSApp.terminate(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(EXIT_SUCCESS)
        }
    }

    static func preferredPopoverSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(460, max(420, visibleFrame.width * 0.24))
        let height = min(430, max(360, visibleFrame.height - 220))

        return NSSize(width: width, height: height)
    }

    static func preferredSystemMonitorPanelSize() -> NSSize {
        SystemMonitorPanelSizing.preferredSize()
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

    static func toolboxStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { rect in
            NSColor.labelColor.setFill()

            let mark = NSBezierPath()
            mark.windingRule = .evenOdd

            mark.append(Self.invertedPentagramPath(in: rect.insetBy(dx: 1.1, dy: 1.1)))

            let dYOffset: CGFloat = -0.2
            let dLeftExtent: CGFloat = rect.minX + 7.0
            let dRightExtent: CGFloat = rect.minX + 12.2
            let dWidth = dRightExtent - dLeftExtent
            let outerShoulderX = dLeftExtent + (dWidth * 0.28)
            let innerLeftExtent = dLeftExtent + 1.05
            let innerShoulderX = outerShoulderX - 0.15
            let innerRightExtent = dRightExtent - 1.3

            let outerD = NSBezierPath()
            outerD.move(to: NSPoint(x: dLeftExtent, y: rect.minY + 5.5 + dYOffset))
            outerD.line(to: NSPoint(x: dLeftExtent, y: rect.maxY - 5.5 + dYOffset))
            outerD.line(to: NSPoint(x: outerShoulderX, y: rect.maxY - 5.5 + dYOffset))
            outerD.curve(
                to: NSPoint(x: outerShoulderX, y: rect.minY + 5.5 + dYOffset),
                controlPoint1: NSPoint(x: dRightExtent, y: rect.maxY - 5.5 + dYOffset),
                controlPoint2: NSPoint(x: dRightExtent, y: rect.minY + 5.5 + dYOffset)
            )
            outerD.close()
            mark.append(outerD)

            let innerCounter = NSBezierPath()
            innerCounter.move(to: NSPoint(x: innerLeftExtent, y: rect.minY + 6.55 + dYOffset))
            innerCounter.line(to: NSPoint(x: innerLeftExtent, y: rect.maxY - 6.55 + dYOffset))
            innerCounter.line(to: NSPoint(x: innerShoulderX, y: rect.maxY - 6.55 + dYOffset))
            innerCounter.curve(
                to: NSPoint(x: innerShoulderX, y: rect.minY + 6.55 + dYOffset),
                controlPoint1: NSPoint(x: innerRightExtent, y: rect.maxY - 6.55 + dYOffset),
                controlPoint2: NSPoint(x: innerRightExtent, y: rect.minY + 6.55 + dYOffset)
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

    private static func invertedPentagramPath(in rect: NSRect) -> NSBezierPath {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        let path = NSBezierPath()

        for index in 0..<10 {
            let isOuterPoint = index.isMultiple(of: 2)
            let radius = isOuterPoint ? outerRadius : innerRadius
            let angle = (-CGFloat.pi / 2) + (CGFloat(index) * CGFloat.pi / 5)
            let point = NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        path.close()
        return path
    }
}
