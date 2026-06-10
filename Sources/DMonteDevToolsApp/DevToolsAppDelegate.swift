import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class DevToolsAppDelegate: NSObject, NSApplicationDelegate {
    private static let showWindowNotification = Notification.Name("com.havokentity.mactools.devtools.showWindow")

    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "Dev Tools",
                sizing: .fixed(preferredSize: { DevToolsSizing.preferredSize() })
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: DevToolsWindowView(
                        onQuit: {
                            self?.quitDevTools()
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
        host.observeShowNotification(named: Self.showWindowNotification)

        DispatchQueue.main.async { [weak self] in
            self?.windowHost?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowHost?.tearDownForTermination()
    }

    private func quitDevTools() {
        NSApp.terminate(nil)
    }
}
