import AppKit
import DMonteCore

let singleInstanceGuard = SingleInstanceGuard(identifier: "com.havokentity.mactools.systemmonitor")

guard singleInstanceGuard.isPrimary else {
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = SystemMonitorAppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
