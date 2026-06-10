import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class GrabTextAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: HelperStatusItem?
    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "DMonte Grab Text",
                sizing: .fixed(preferredSize: { GrabTextSizing.preferredSize() })
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: GrabTextWindowView(
                        onQuit: {
                            self?.quitGrabText()
                        }
                    )
                )
            },
            onUserClosedWindow: { [weak self] in
                if self?.statusItem == nil {
                    NSApp.terminate(nil)
                }
            }
        )
        windowHost = host
        host.configureWindow()

        let icon = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Grab Text") ?? NSImage()
        statusItem = HelperStatusItem(
            image: icon,
            toolTip: "Grab Text",
            primaryAction: { [weak self] in
                self?.windowHost?.show(relativeTo: self?.statusItem?.button)
            },
            quitAction: { [weak self] in self?.quitGrabText() }
        )

        host.observeShowNotification(named: grabTextShowWindowNotification)

        if CommandLine.arguments.contains("--open") || statusItem == nil {
            DispatchQueue.main.async { [weak self] in
                self?.windowHost?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowHost?.tearDownForTermination()
        statusItem?.remove()
    }

    private func quitGrabText() {
        NSApp.terminate(nil)
    }
}
