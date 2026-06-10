import AppKit
import SwiftUI
import DMonteCore

@MainActor
final class AudioSwitcherAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelHost: HelperPanelHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperPanelHost(
            configuration: HelperPanelHost.Configuration(
                styleMask: [.borderless, .nonactivatingPanel],
                isFloatingPanel: nil,
                hidesOnDeactivate: nil,
                isReleasedWhenClosed: nil,
                creation: .onFirstShow,
                sizing: .fixedAtCreation(
                    NSSize(width: AudioSwitcherSizing.panelWidth, height: AudioSwitcherSizing.panelHeight)
                ),
                activation: .orderFrontThenActivate,
                clickMonitorInstall: .immediate,
                positioning: .anchoredOriginRawBounds(gap: 8)
            ),
            content: .view({ [weak self] in
                let content = AudioSwitcherPopoverView(onQuit: {
                    self?.quit()
                })
                return NSHostingView(rootView: content)
            }),
            anchorView: { [weak self] in self?.statusItem?.button }
        )
        panelHost = host

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "hifispeaker.fill",
                accessibilityDescription: "Audio Switcher"
            )
            button.image?.isTemplate = true
            button.toolTip = "Audio Switcher"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        host.observeShowNotification(named: Notification.Name("com.havokentity.mactools.audioswitcher.showWindow"))
    }

    @objc private func togglePopover() {
        if StatusBarButtonContent.popUpQuitMenuIfNeeded(for: statusItem, action: { [weak self] in
            self?.quit()
        }) {
            return
        }

        panelHost?.toggle()
    }

    private func quit() {
        cleanup()
        NSApp.terminate(nil)
    }

    private func cleanup() {
        panelHost?.removeOutsideClickMonitor()
        panelHost?.stopObservingShowNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }
}
