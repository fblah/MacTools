import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class DuplicateFinderAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: HelperStatusItem?
    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "Duplicate Finder",
                sizing: .fixed(preferredSize: { DuplicateFinderSizing.preferredSize() })
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: DuplicateFinderWindowView(
                        onQuit: {
                            self?.quit()
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

        let icon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Duplicate Finder") ?? NSImage()
        statusItem = HelperStatusItem(
            image: icon,
            toolTip: "Duplicate Finder",
            primaryAction: { [weak self] in
                self?.windowHost?.show(relativeTo: self?.statusItem?.button)
            },
            quitAction: { [weak self] in self?.quit() }
        )

        host.observeShowNotification(named: Notification.Name("com.havokentity.mactools.duplicatefinder.showWindow"))

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

    private func quit() {
        NSApp.terminate(nil)
    }
}
