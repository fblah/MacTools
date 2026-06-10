import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class CleanDriveAppDelegate: NSObject, NSApplicationDelegate {
    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "Clean Drive",
                sizing: .fixed(preferredSize: { CleanDriveSizing.preferredSize() })
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: CleanDriveWindowView(
                        onQuit: {
                            self?.quitCleanDrive()
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
        host.observeShowNotification(named: HelperNotifications.showCleanDriveWindow)

        DispatchQueue.main.async { [weak self] in
            self?.windowHost?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowHost?.tearDownForTermination()
    }

    private func quitCleanDrive() {
        NSApp.terminate(nil)
    }
}
