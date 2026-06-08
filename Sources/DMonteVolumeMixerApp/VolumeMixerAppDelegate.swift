import AppKit
import DMonteCore
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class VolumeMixerAppDelegate: NSObject, NSApplicationDelegate {
    private static let showWindowNotification =
        Notification.Name("com.havokentity.mactools.volumemixer.showWindow")

    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var outsideClickMonitor: Any?
    private var showWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "slider.horizontal.3",
                accessibilityDescription: "Volume Mixer"
            )
            button.image?.isTemplate = true
            button.toolTip = "Volume Mixer"
            button.target = self
            button.action = #selector(togglePopover)
        }
        self.statusItem = statusItem

        showWindowObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showPopover()
            }
        }
    }

    @objc private func togglePopover() {
        if let panel, panel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let panelToShow: KeyablePanel
        if let existing = panel {
            panelToShow = existing
        } else {
            let newPanel = makePanel()
            panel = newPanel
            panelToShow = newPanel
        }

        positionPanel(panelToShow)
        panelToShow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        addOutsideClickMonitor()
    }

    private func closePopover() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyablePanel {
        let content = VolumeMixerPopoverView(onQuit: { [weak self] in
            self?.quit()
        })
        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 18
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true

        let panel = KeyablePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: VolumeMixerSizing.panelWidth,
                height: VolumeMixerSizing.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionPanel(_ panel: KeyablePanel) {
        guard let button = statusItem?.button, let screen = button.window?.screen else { return }
        let buttonFrame = button.window?.convertToScreen(button.bounds) ?? .zero
        var x = buttonFrame.midX - VolumeMixerSizing.panelWidth / 2
        var y = buttonFrame.minY - 8 - VolumeMixerSizing.panelHeight
        let visible = screen.visibleFrame
        x = max(visible.minX + 8, min(x, visible.maxX - VolumeMixerSizing.panelWidth - 8))
        if y < visible.minY + 8 { y = visible.minY + 8 }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func addOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
    }

    private func quit() {
        cleanup()
        NSApp.terminate(nil)
    }

    private func cleanup() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let observer = showWindowObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            showWindowObserver = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }
}
