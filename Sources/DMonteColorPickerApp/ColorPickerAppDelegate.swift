import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class ColorPickerAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelHost: HelperPanelHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        configurePanelHost()
        setUpStatusItem()
        panelHost?.observeShowNotification(named: Notification.Name("com.havokentity.mactools.colorpicker.showWindow"))
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelHost?.removeOutsideClickMonitor()
    }

    // MARK: - Panel host

    private func configurePanelHost() {
        // A non-activating panel that can still become key, so the embedded SwiftUI text
        // fields and buttons receive keyboard/mouse input. Unlike the other tools the
        // content draws its own shape (no shared corner-radius treatment) and the panel
        // never set a collection behaviour.
        let host = HelperPanelHost(
            configuration: HelperPanelHost.Configuration(
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                collectionBehavior: nil,
                isReleasedWhenClosed: nil,
                isMovableByWindowBackground: false,
                hidesTitleBarChrome: true,
                cornerRadius: nil,
                creation: .onFirstShow,
                sizing: .fixedAtCreation(ColorPickerSizing.preferredSize()),
                activation: .orderFrontThenActivate,
                clickMonitorInstall: .immediate,
                positioning: .anchoredOriginOrAbort(gap: 6)
            ),
            content: .viewController({ [weak self] in
                NSHostingController(
                    rootView: ColorPickerPopoverView(onQuit: {
                        self?.quit()
                    })
                )
            }),
            anchorView: { [weak self] in self?.statusItem?.button }
        )
        panelHost = host
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = NSImage(
                systemSymbolName: "eyedropper.halffull",
                accessibilityDescription: "Color Picker"
            )?.withSymbolConfiguration(config)
            button.image = image
            button.toolTip = "Color Picker"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
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
        NSApp.terminate(nil)
    }
}
