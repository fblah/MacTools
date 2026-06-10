import AppKit
import DMonteCore

/// The distributed-notification this helper posts (when re-launched with `--open` while
/// already running) and observes (in its delegate) to reveal its window. Matches the
/// toolbox convention of `<bundleID>.showWindow`.
let imageConverterShowWindowNotification = Notification.Name("com.havokentity.mactools.imageconverter.showWindow")

let singleInstanceGuard = SingleInstanceGuard(identifier: "com.havokentity.mactools.imageconverter")

guard singleInstanceGuard.isPrimary else {
    if CommandLine.arguments.contains("--open") {
        DistributedNotificationCenter.default().postNotificationName(
            imageConverterShowWindowNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = ImageConverterAppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
