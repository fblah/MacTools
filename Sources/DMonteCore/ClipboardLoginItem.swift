import Foundation
import Darwin

/// Registers the clipboard helper as a per-user LaunchAgent so it starts at login and keeps
/// capturing copies. Mirrors `SystemMonitorLoginItem`; disabled by default so opening the Toolbox
/// does not spawn helpers until the user opts in.
@MainActor
public enum ClipboardLoginItem {
    private static let label = "com.havokentity.mactools.clipboard"

    public static func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            install()
        } else {
            uninstall()
        }
    }

    public static func refreshIfEnabled() {
        guard AppDefaults.shared.bool(forKey: DefaultsKey.clipboardOpenAtLogin) else {
            uninstall()
            return
        }

        install()
    }

    /// Repairs an installed LaunchAgent whose recorded helper path has gone stale — e.g. the
    /// "DMonte Toolbox.app" → "DMonte Tool Box.app" rename deleted the bundle path the agent
    /// pointed at, so launchd failed silently at login and the helper never got a chance to
    /// rewrite the plist itself. Called from the main Tool Box app at launch with the path the
    /// helper's own `Bundle.main.executableURL` would report when run from inside the current
    /// bundle (Contents/Helpers/<App>.app/Contents/MacOS/<exe>).
    ///
    /// No-op unless the agent is actually installed (plist on disk — preserving the user's
    /// enabled/disabled choice) and its recorded path is dead or differs from `expectedPath`.
    /// Costs at most two small file reads when there is nothing to do.
    public static func migrateInstalledAgentIfNeeded(toExecutablePath expectedPath: String) {
        guard FileManager.default.fileExists(atPath: expectedPath),
              let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let recordedPath = (plist["ProgramArguments"] as? [String])?.first else {
            return
        }

        if recordedPath == expectedPath, FileManager.default.fileExists(atPath: recordedPath) {
            return
        }

        install(executablePath: expectedPath)
    }

    private static func install() {
        guard let executablePath = Bundle.main.executableURL?.path else {
            return
        }

        install(executablePath: executablePath)
    }

    private static func install(executablePath: String) {
        do {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]

            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )

            if let existingData = try? Data(contentsOf: launchAgentURL),
               existingData == data {
                return
            }

            try data.write(to: launchAgentURL, options: .atomic)
            reloadLaunchAgent()
        } catch {
            AppDefaults.shared.set(false, forKey: DefaultsKey.clipboardOpenAtLogin)
        }
    }

    private static func uninstall() {
        unloadLaunchAgent()
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func reloadLaunchAgent() {
        unloadLaunchAgent()
        runLaunchctl(arguments: ["bootstrap", guiDomain, launchAgentURL.path])
    }

    private static func unloadLaunchAgent() {
        runLaunchctl(arguments: ["bootout", guiDomain, launchAgentURL.path])
    }

    private static func runLaunchctl(arguments: [String]) {
        guard FileManager.default.fileExists(atPath: "/bin/launchctl") else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    private static var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
    }
}
