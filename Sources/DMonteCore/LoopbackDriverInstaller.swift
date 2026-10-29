import CoreAudio
import Foundation

/// Installs / removes the bundled BlackHole loopback driver for the Audio Router
/// tool. The driver ships inside the app's Resources (re-signed with our
/// Developer ID); installing copies it to the system HAL plug-in directory and
/// reloads `coreaudiod`, which requires admin rights — so the privileged steps
/// run through an `osascript` "with administrator privileges" prompt.
///
/// The shell/AppleScript construction is split into pure, unit-tested helpers;
/// only the actual `Process` execution touches the system.
public enum LoopbackDriverInstaller {

    /// The system directory CoreAudio loads HAL plug-ins from.
    public static let halPluginDirectory = "/Library/Audio/Plug-Ins/HAL"

    public enum InstallError: Error, Equatable {
        /// This build shipped without a bundled driver (e.g. `swift run`).
        case driverNotBundled
        /// The user dismissed the admin authorization prompt.
        case authorizationCancelled
        /// The privileged command exited non-zero.
        case commandFailed(Int32, String)

        public var message: String {
            switch self {
            case .driverNotBundled:
                return "No loopback driver is bundled in this build"
            case .authorizationCancelled:
                return "Installation cancelled"
            case .commandFailed(let status, let output):
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty ? "Install failed (status \(status))" : detail
            }
        }
    }

    // MARK: - Cable model

    /// The transport type a cable reports to CoreAudio. Every cable ships in
    /// both flavours with the same identity: apps that only list hardware
    /// devices (e.g. WhatsApp) hide `.virtual` cables but show `.usb` ones.
    public enum Transport: String, CaseIterable, Identifiable, Sendable {
        case virtual
        case usb

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .virtual: return "Virtual"
            case .usb: return "USB"
            }
        }

        /// Maps a `kAudioDevicePropertyTransportType` value; `nil` for anything
        /// other than the two transports our cables are built with.
        public init?(coreAudioTransportType: UInt32) {
            switch coreAudioTransportType {
            case kAudioDeviceTransportTypeVirtual: self = .virtual
            case kAudioDeviceTransportTypeUSB: self = .usb
            default: return nil
            }
        }
    }

    /// One installable virtual cable from the bundled pool. Each is an
    /// independent BlackHole instance with its own device UID, so multiple can
    /// be installed and used simultaneously (e.g. one for Discord, one for Zoom).
    public struct LoopbackCable: Identifiable, Sendable, Equatable {
        /// Stable id = the driver bundle's base name, e.g. `DMonteCable1`.
        public let id: String
        /// Friendly label shown in our UI, e.g. `DMonte Cable 1`.
        public let displayName: String
        /// How the device appears to other apps (Discord/Zoom/…), e.g.
        /// `DMonte Cable 1` — the driver's `kDevice_Name` is built with the
        /// friendly spaced form.
        public let deviceName: String
        /// Location of the (virtual-transport) `.driver` bundle inside the
        /// app's Resources.
        public let driverURL: URL
        /// The USB-transport build of the same cable, when this build ships one.
        public let usbDriverURL: URL?

        public var driverFileName: String { driverURL.lastPathComponent }

        /// Whether the cable can be switched between virtual and USB.
        public var supportsTransportSwitch: Bool { usbDriverURL != nil }

        /// The CoreAudio device UID BlackHole derives from the driver name:
        /// `kDriver_Name` + `<channels>ch_UID`, and our cables are 2-channel.
        public var deviceUID: String { id + "2ch_UID" }

        /// The bundled driver for `transport`, or `nil` if not shipped.
        public func driverURL(for transport: Transport) -> URL? {
            switch transport {
            case .virtual: return driverURL
            case .usb: return usbDriverURL
            }
        }

        public init(
            id: String,
            displayName: String,
            deviceName: String,
            driverURL: URL,
            usbDriverURL: URL? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.deviceName = deviceName
            self.driverURL = driverURL
            self.usbDriverURL = usbDriverURL
        }
    }

    // MARK: - Discovery

    /// The directory in the app's Resources holding the bundled cable pool.
    static func cablesDirectory(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("Cables", isDirectory: true)
    }

    /// Subfolder of the pool holding each cable's USB-transport build.
    static let usbSubdirectory = "USB"

    /// Every virtual cable bundled with this build, sorted by index. Empty when
    /// the build shipped without a pool (e.g. `swift run`, or an offline build).
    public static func bundledCables(in bundle: Bundle = .main) -> [LoopbackCable] {
        guard let dir = cablesDirectory(in: bundle) else { return [] }
        return cables(inDirectory: dir)
    }

    /// Pure directory scan: every `*.driver` in `directory` mapped to a cable,
    /// natural-sorted by index, each paired with its USB-transport build from
    /// the `USB` subfolder when one exists. Non-driver entries (including that
    /// subfolder) are ignored.
    static func cables(inDirectory directory: URL) -> [LoopbackCable] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let usbDirectory = directory.appendingPathComponent(usbSubdirectory, isDirectory: true)
        return urls
            .filter { $0.pathExtension == "driver" }
            .map { url in
                let driverID = url.deletingPathExtension().lastPathComponent
                let friendly = friendlyName(forDriverID: driverID)
                let usbURL = usbDirectory.appendingPathComponent(url.lastPathComponent)
                return LoopbackCable(
                    id: driverID,
                    displayName: friendly,
                    // The driver's kDevice_Name is the friendly form, so this is
                    // exactly how the cable appears in other apps' device menus.
                    deviceName: friendly,
                    driverURL: url,
                    usbDriverURL: FileManager.default.fileExists(atPath: usbURL.path) ? usbURL : nil
                )
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Whether this build bundles any cables to install.
    public static func canManageCables(in bundle: Bundle = .main) -> Bool {
        !bundledCables(in: bundle).isEmpty
    }

    /// Where a cable's driver lands once installed.
    public static func installedURL(for cable: LoopbackCable) -> URL {
        URL(fileURLWithPath: halPluginDirectory).appendingPathComponent(cable.driverFileName)
    }

    /// Whether a specific cable is currently installed in the HAL directory.
    public static func isInstalled(_ cable: LoopbackCable) -> Bool {
        FileManager.default.fileExists(atPath: installedURL(for: cable).path)
    }

    /// The transport an installed cable is reporting right now, read from
    /// CoreAudio itself so it reflects whichever variant is actually loaded.
    /// `nil` when the cable's device isn't loaded (e.g. CoreAudio is still
    /// restarting after an install) or reports an unexpected transport.
    public static func installedTransport(of cable: LoopbackCable) -> Transport? {
        guard let deviceID = AudioRouterKit.deviceID(forUID: cable.deviceUID) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType) == noErr else {
            return nil
        }
        return Transport(coreAudioTransportType: transportType)
    }

    /// Where a bundled driver would land once installed (used by the pure tests).
    public static func installedDriverURL(forBundled bundled: URL) -> URL {
        URL(fileURLWithPath: halPluginDirectory)
            .appendingPathComponent(bundled.lastPathComponent)
    }

    /// Turns a space-free driver id into a friendly label:
    /// `DMonteCable1` → `DMonte Cable 1`. Inserts a space at lower→upper and
    /// letter→digit boundaries.
    static func friendlyName(forDriverID driverID: String) -> String {
        var result = ""
        for character in driverID {
            if let last = result.last,
               (last.isLowercase && character.isUppercase) ||
               (last.isLetter && character.isNumber) {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    // MARK: - Command construction (pure)

    /// POSIX-single-quotes a path so it survives `/bin/sh` intact.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Shell that installs `source` (a `.driver`) into `destinationDirectory` and
    /// reloads CoreAudio.
    static func installShellCommand(
        source: String,
        destinationDirectory: String = halPluginDirectory
    ) -> String {
        let destination = destinationDirectory + "/" + (source as NSString).lastPathComponent
        return [
            "mkdir -p \(shellQuote(destinationDirectory))",
            "rm -rf \(shellQuote(destination))",
            "cp -R \(shellQuote(source)) \(shellQuote(destination))",
            "killall coreaudiod"
        ].joined(separator: " && ")
    }

    /// Shell that removes an installed driver and reloads CoreAudio.
    static func uninstallShellCommand(driverPath: String) -> String {
        "rm -rf \(shellQuote(driverPath)) && killall coreaudiod"
    }

    /// Wraps a shell command in an AppleScript that runs it with admin rights,
    /// escaping it for the AppleScript string literal.
    static func adminAppleScript(forShellCommand command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    // MARK: - Execution

    @discardableResult
    static func runPrivileged(_ shellCommand: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", adminAppleScript(forShellCommand: shellCommand)]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let errText = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            // osascript reports a user-dismissed auth dialog as error -128.
            if errText.contains("-128") || errText.localizedCaseInsensitiveContains("cancel") {
                throw InstallError.authorizationCancelled
            }
            throw InstallError.commandFailed(process.terminationStatus, errText)
        }
        return String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }

    // MARK: - Public actions

    /// Copies the cable's driver for `transport` into the HAL directory and
    /// reloads CoreAudio. Both variants share a file name, so installing one
    /// over the other is how a cable switches transport. Blocks on the admin
    /// prompt — call off the main thread.
    public static func install(_ cable: LoopbackCable, transport: Transport = .virtual) throws {
        guard let source = cable.driverURL(for: transport),
              FileManager.default.fileExists(atPath: source.path) else {
            throw InstallError.driverNotBundled
        }
        try runPrivileged(installShellCommand(source: source.path))
    }

    /// Removes an installed cable's driver and reloads CoreAudio.
    public static func uninstall(_ cable: LoopbackCable) throws {
        try runPrivileged(uninstallShellCommand(driverPath: installedURL(for: cable).path))
    }
}
