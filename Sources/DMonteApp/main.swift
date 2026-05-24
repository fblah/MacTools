import AppKit

let app = NSApplication.shared
let delegate: NSApplicationDelegate = if CommandLine.arguments.contains("--preview-ui") {
    PreviewAppDelegate()
} else {
    AppDelegate()
}

app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--preview-ui") ? .regular : .accessory)
app.run()
