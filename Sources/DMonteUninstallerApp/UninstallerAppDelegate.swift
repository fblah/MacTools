import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class UninstallerAppDelegate: NSObject, NSApplicationDelegate {
    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "Uninstall Apps",
                sizing: .fixed(preferredSize: { UninstallerSizing.windowSize })
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: UninstallerPopoverView(
                        onQuit: {
                            self?.quitUninstaller()
                        }
                    )
                )
            },
            onUserClosedWindow: {
                NSApp.terminate(nil)
            }
        )
        windowHost = host
        host.configureWindow()
        host.observeShowNotification(named: HelperNotifications.showUninstallerWindow)

        DispatchQueue.main.async { [weak self] in
            self?.windowHost?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowHost?.tearDownForTermination()
    }

    private func quitUninstaller() {
        NSApp.terminate(nil)
    }
}
