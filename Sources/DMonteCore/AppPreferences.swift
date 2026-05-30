import Foundation

public enum DefaultsKey {
    public static let videoDownloaderPreferredQuality = "tool.videoDownloader.preferredQuality"
    public static let videoDownloaderNonMP4Handling = "tool.videoDownloader.nonMP4Handling"
    public static let videoDownloaderDownloadsSubtitles = "tool.videoDownloader.downloadsSubtitles"
    public static let videoDownloaderSaveDirectory = "tool.videoDownloader.saveDirectory"
    public static let videoDownloaderCookieSource = "tool.videoDownloader.cookieSource"
    public static let systemMonitorTemperatureUnit = "tool.systemMonitor.temperatureUnit"
    public static let systemMonitorOpenAtLogin = "tool.systemMonitor.openAtLogin"
    public static let systemMonitorShowsTrayIcon = "tool.systemMonitor.showsTrayIcon"
    public static let clipboardOpenAtLogin = "tool.clipboard.openAtLogin"
    public static let clipboardMaxHistory = "tool.clipboard.maxHistory"
    public static let grabTextCopyAutomatically = "tool.grabText.copyAutomatically"

    static let obsoleteKeys = [
        "tool.systemMonitor.enabled",
        "tool.uninstaller.enabled",
        "tool.uninstaller.tray.enabled",
        "tool.cleanDrive.enabled",
        "tool.cleanDrive.tray.enabled",
        "tool.videoDownloader.enabled",
        "tool.videoDownloader.tray.enabled"
    ]
}

@MainActor
public enum AppDefaults {
    public static let shared = UserDefaults(suiteName: "com.havokentity.mactools.shared") ?? .standard

    public static func registerDefaults() {
        DefaultsKey.obsoleteKeys.forEach { shared.removeObject(forKey: $0) }

        shared.register(defaults: [
            DefaultsKey.videoDownloaderPreferredQuality: VideoQuality.maximum.rawValue,
            DefaultsKey.videoDownloaderNonMP4Handling: VideoNonMP4Handling.downloadWithoutConversion.rawValue,
            DefaultsKey.videoDownloaderDownloadsSubtitles: true,
            DefaultsKey.videoDownloaderSaveDirectory: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
            DefaultsKey.videoDownloaderCookieSource: VideoCookieSource.automatic.rawValue,
            DefaultsKey.systemMonitorTemperatureUnit: TemperatureUnitPreference.celsius.rawValue,
            DefaultsKey.systemMonitorOpenAtLogin: false,
            DefaultsKey.systemMonitorShowsTrayIcon: true,
            DefaultsKey.clipboardOpenAtLogin: true,
            DefaultsKey.clipboardMaxHistory: 200,
            DefaultsKey.grabTextCopyAutomatically: true,
            DefaultsKey.focusTimerFocusMinutes: 25,
            DefaultsKey.focusTimerShortBreakMinutes: 5,
            DefaultsKey.focusTimerLongBreakMinutes: 15,
            DefaultsKey.focusTimerLongBreakInterval: 4
        ])
    }
}
