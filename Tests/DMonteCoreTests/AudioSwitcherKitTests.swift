import XCTest
import CoreAudio
@testable import DMonteCore

/// Environment-tolerant tests for the spec-facing `AudioSwitcherKit`. CoreAudio
/// depends on real hardware, so CI / headless machines may expose zero devices.
/// These assert structural correctness rather than the presence of any specific
/// device, and never call a `setDefault*` (which would change the user's audio).
/// Mirrors the DevToolsTests style: robust, non-flaky, no side effects.
final class AudioSwitcherKitTests: XCTestCase {

    func testDevicesReturnsArrayWithoutCrashing() {
        // Must simply return without crashing; count is environment-dependent.
        let devices = AudioSwitcherKit.devices()
        XCTAssertGreaterThanOrEqual(devices.count, 0)
    }

    func testEveryDeviceHasANonEmptyName() {
        for device in AudioSwitcherKit.devices() {
            XCTAssertFalse(
                device.name.isEmpty,
                "Enumerated devices should always have a non-empty name"
            )
        }
    }

    func testEveryDeviceExposesAtLeastOneDirection() {
        for device in AudioSwitcherKit.devices() {
            XCTAssertTrue(
                device.hasOutput || device.hasInput,
                "Device \(device.name) should expose at least one stream direction"
            )
        }
    }

    func testDefaultOutputIDIsListedWhenPresent() {
        guard let defaultID = AudioSwitcherKit.defaultOutputID() else {
            // No default output on this machine (valid in headless/CI).
            return
        }
        let ids = AudioSwitcherKit.devices().map(\.id)
        XCTAssertTrue(
            ids.contains(defaultID),
            "Default output id should appear among the enumerated device ids"
        )
    }

    func testDefaultInputIDIsListedWhenPresent() {
        guard let defaultID = AudioSwitcherKit.defaultInputID() else {
            return
        }
        let ids = AudioSwitcherKit.devices().map(\.id)
        XCTAssertTrue(
            ids.contains(defaultID),
            "Default input id should appear among the enumerated device ids"
        )
    }

    func testDefaultOutputIsAnOutputDeviceWhenPresent() {
        guard let defaultID = AudioSwitcherKit.defaultOutputID(),
              let device = AudioSwitcherKit.devices().first(where: { $0.id == defaultID }) else {
            return
        }
        XCTAssertTrue(device.hasOutput, "The default output device should expose output streams")
    }

    func testAudioDeviceEquatableAndIdentifiable() {
        let a = AudioDevice(id: 42, name: "Speakers", uid: "uid-42", hasOutput: true, hasInput: false)
        let b = AudioDevice(id: 42, name: "Speakers", uid: "uid-42", hasOutput: true, hasInput: false)
        let c = AudioDevice(id: 99, name: "Mic", uid: "uid-99", hasOutput: false, hasInput: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.id, AudioDeviceID(42))
    }

    func testAppVolumeTargetClampsGain() {
        XCTAssertEqual(AppVolumeTarget.clampGain(-0.5), 0)
        XCTAssertEqual(AppVolumeTarget.clampGain(0.4), 0.4)
        XCTAssertEqual(AppVolumeTarget.clampGain(2), 1)
    }

    func testAppVolumeTargetUsesBundleIDAsStableIdentity() {
        let target = AppVolumeTarget(
            processID: 123,
            audioObjectID: 456,
            bundleIdentifier: "com.example.Player",
            displayName: "Player",
            isRunningOutput: true,
            gain: 0.7
        )
        XCTAssertEqual(target.id, "com.example.Player")
        XCTAssertEqual(target.stableKey, "com.example.Player")
    }

    func testAppVolumeTargetFallsBackToNameIdentity() {
        // Bundle-less audio processes (mpv, afplay, bare binaries) key on
        // their display name so gains/pins survive relaunches under new PIDs.
        let target = AppVolumeTarget(
            processID: 123,
            audioObjectID: 456,
            bundleIdentifier: nil,
            displayName: "mpv",
            isRunningOutput: true,
            gain: 0.7
        )
        XCTAssertEqual(target.id, "name:mpv")
        XCTAssertEqual(target.stableKey, "name:mpv")
    }

    func testStableKeySchemesAgree() {
        // `AppVolumeTarget.stableKey` (the write path) and the shared static
        // key function (used by the kit's discovery/read path) must agree,
        // or persisted gains and pins silently reset every refresh.
        let withBundleID = AppVolumeTarget(
            processID: 123,
            audioObjectID: 456,
            bundleIdentifier: "com.example.Player",
            displayName: "Player",
            isRunningOutput: true,
            gain: 1
        )
        XCTAssertEqual(
            withBundleID.stableKey,
            AppVolumeTarget.stableKey(
                processID: 123,
                bundleIdentifier: "com.example.Player",
                displayName: "Player"
            )
        )

        let withoutBundleID = AppVolumeTarget(
            processID: 123,
            audioObjectID: 456,
            bundleIdentifier: nil,
            displayName: "mpv",
            isRunningOutput: true,
            gain: 1
        )
        XCTAssertEqual(
            withoutBundleID.stableKey,
            AppVolumeTarget.stableKey(processID: 123, bundleIdentifier: nil, displayName: "mpv")
        )
        XCTAssertEqual(withoutBundleID.stableKey, "name:mpv")

        // PID fallback only remains for processes with no usable name.
        XCTAssertEqual(
            AppVolumeTarget.stableKey(processID: 123, bundleIdentifier: "", displayName: ""),
            "pid:123"
        )
        XCTAssertEqual(
            AppVolumeTarget.stableKey(processID: 123, bundleIdentifier: nil, displayName: nil),
            "pid:123"
        )
    }

    func testAppVolumeGainRoundTripsForTargetWithoutBundleIdentifier() {
        let suiteName = "AppVolumeMixerTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer {
            suite.removePersistentDomain(forName: suiteName)
        }
        let target = AppVolumeTarget(
            processID: 321,
            audioObjectID: 654,
            bundleIdentifier: nil,
            displayName: "mpv",
            isRunningOutput: true,
            gain: 1
        )

        AppVolumeMixerKit.setGain(0.5, for: target, defaults: suite)

        XCTAssertEqual(AppVolumeMixerKit.gain(for: target, defaults: suite), 0.5)
        XCTAssertEqual(AppVolumeMixerKit.persistedGains(defaults: suite)["name:mpv"], 0.5)
    }

    func testAppVolumeGainPersistenceClampsValues() {
        let suiteName = "AppVolumeMixerTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer {
            suite.removePersistentDomain(forName: suiteName)
        }
        let target = AppVolumeTarget(
            processID: 123,
            audioObjectID: 456,
            bundleIdentifier: "com.example.Player",
            displayName: "Player",
            isRunningOutput: true,
            gain: 1
        )

        AppVolumeMixerKit.setGain(2, for: target, defaults: suite)

        XCTAssertEqual(AppVolumeMixerKit.gain(for: target, defaults: suite), 1)
        XCTAssertEqual(
            AppVolumeMixerKit.persistedGains(defaults: suite)["com.example.Player"],
            1
        )
    }
}
