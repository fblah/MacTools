import AppKit
import DMonteCore
import SwiftUI

@MainActor
final class DiskAnalyzerAppDelegate: NSObject, NSApplicationDelegate {
    private static let minimumContentSize = NSSize(width: 760, height: 460)

    private var windowHost: HelperWindowHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()

        // Titled + full-size content keeps the frosted, chrome-less look while
        // allowing the user to resize the window and enter native full screen.
        let host = HelperWindowHost(
            configuration: HelperWindowHost.Configuration(
                title: "Disk Usage Analyzer",
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                collectionBehavior: [.canJoinAllSpaces, .fullScreenPrimary],
                hidesTitleBarChrome: true,
                sizing: .resizable(
                    initialSize: { DiskAnalyzerSizing.preferredSize() },
                    minimumContentSize: Self.minimumContentSize
                )
            ),
            makeContent: { [weak self] in
                NSHostingController(
                    rootView: DiskAnalyzerWindowView(
                        onQuit: {
                            self?.quitDiskAnalyzer()
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
        host.observeShowNotification(named: HelperNotifications.showDiskAnalyzerWindow)

        DispatchQueue.main.async { [weak self] in
            self?.windowHost?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowHost?.tearDownForTermination()
    }

    private func quitDiskAnalyzer() {
        NSApp.terminate(nil)
    }
}
