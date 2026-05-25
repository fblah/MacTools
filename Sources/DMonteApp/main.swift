import AppKit
import DMonteCore

let isPreviewingUI = CommandLine.arguments.contains("--preview-ui")
let singleInstanceGuard = isPreviewingUI ? nil : SingleInstanceGuard(identifier: "com.havokentity.mactools")

guard singleInstanceGuard?.isPrimary ?? true else {
    DistributedNotificationCenter.default().postNotificationName(
        HelperNotifications.showToolboxWindow,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )

    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate: NSApplicationDelegate = if isPreviewingUI {
    PreviewAppDelegate()
} else {
    AppDelegate()
}

app.delegate = delegate
app.setActivationPolicy(isPreviewingUI ? .regular : .accessory)
app.run()
