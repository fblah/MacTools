import AppKit
import SwiftUI

public enum CleanDriveCategoryID: String, CaseIterable, Identifiable, Sendable {
    case logs
    case caches
    case trash
    case browserData
    case mailCache
    case mobileApps
    case iTunesTemp
    case iOSBackups
    case oldUpdates

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: "Log files"
        case .caches: "Cache files"
        case .trash: "Trash"
        case .browserData: "Browser data"
        case .mailCache: "Mail cache"
        case .mobileApps: "Mobile apps"
        case .iTunesTemp: "iTunes temp files"
        case .iOSBackups: "iOS device backups"
        case .oldUpdates: "Old updates"
        }
    }

    var defaultSelected: Bool {
        self == .logs || self == .caches
    }

    var tint: Color {
        switch self {
        case .logs: .red
        case .caches: .yellow
        default: .secondary
        }
    }

    var targets: [CleanDriveTarget] {
        switch self {
        case .logs:
            [
                CleanDriveTarget("~/Library/Logs", mode: .contents)
            ]
        case .caches:
            [
                CleanDriveTarget("~/Library/Caches", mode: .contents)
            ]
        case .trash:
            [
                CleanDriveTarget("~/.Trash", mode: .contents)
            ]
        case .browserData:
            [
                CleanDriveTarget("~/Library/Caches/Google/Chrome", mode: .item),
                CleanDriveTarget("~/Library/Caches/com.google.Chrome", mode: .item),
                CleanDriveTarget("~/Library/Application Support/Google/Chrome/*/Cache", mode: .item),
                CleanDriveTarget("~/Library/Application Support/Google/Chrome/*/Code Cache", mode: .item),
                CleanDriveTarget("~/Library/Caches/Firefox", mode: .item),
                CleanDriveTarget("~/Library/Application Support/Firefox/Profiles/*/cache2", mode: .item),
                CleanDriveTarget("~/Library/Containers/com.apple.Safari/Data/Library/Caches", mode: .contents)
            ]
        case .mailCache:
            [
                CleanDriveTarget("~/Library/Containers/com.apple.mail/Data/Library/Caches", mode: .contents),
                CleanDriveTarget("~/Library/Containers/com.apple.MailCacheDelete", mode: .contents)
            ]
        case .mobileApps:
            [
                CleanDriveTarget("~/Music/iTunes/iTunes Media/Mobile Applications", mode: .contents)
            ]
        case .iTunesTemp:
            [
                CleanDriveTarget("~/Music/iTunes/iTunes Media/Downloads", mode: .contents),
                CleanDriveTarget("~/Music/Music/Media.localized/Downloads", mode: .contents),
                CleanDriveTarget("~/Library/Caches/com.apple.iTunes", mode: .contents)
            ]
        case .iOSBackups:
            [
                CleanDriveTarget("~/Library/Application Support/MobileSync/Backup", mode: .contents)
            ]
        case .oldUpdates:
            [
                CleanDriveTarget("~/Library/Caches/com.apple.SoftwareUpdate", mode: .contents)
            ]
        }
    }
}

public struct CleanDriveItem: Identifiable, Equatable, Sendable {
    public var id: CleanDriveCategoryID
    public var size: UInt64
    public var targetCount: Int

    public var title: String {
        id.title
    }

    public var defaultSelected: Bool {
        id.defaultSelected
    }
}

struct CleanDriveTarget: Sendable {
    enum Mode: Sendable {
        case item
        case contents
    }

    var path: String
    var mode: Mode

    init(_ path: String, mode: Mode) {
        self.path = path
        self.mode = mode
    }
}

public enum CleanDriveScanner {
    public static func scan() -> [CleanDriveItem] {
        CleanDriveCategoryID.allCases.map { category in
            let expandedTargets = category.targets.flatMap { target in
                resolvedURLs(for: target).map { (url: $0, mode: target.mode) }
            }
            let categorySize = expandedTargets.reduce(UInt64(0)) { total, target in
                total + size(of: target.url, mode: target.mode)
            }

            return CleanDriveItem(id: category, size: categorySize, targetCount: expandedTargets.count)
        }
    }

    public static func clean(categories: Set<CleanDriveCategoryID>) -> CleanDriveResult {
        var cleanedBytes: UInt64 = 0
        var failedPaths: [String] = []

        for category in categories {
            for target in category.targets {
                for url in resolvedURLs(for: target) {
                    let bytes = size(of: url, mode: target.mode)

                    do {
                        try clean(url: url, mode: target.mode, emptiesTrash: category == .trash)
                        cleanedBytes += bytes
                    } catch {
                        failedPaths.append(url.path)
                    }
                }
            }
        }

        return CleanDriveResult(cleanedBytes: cleanedBytes, failedPaths: failedPaths)
    }

    public static func targetSummary(for categories: Set<CleanDriveCategoryID>) -> (itemCount: Int, includesTrash: Bool) {
        var itemCount = 0

        for category in categories {
            for target in category.targets {
                for url in resolvedURLs(for: target) {
                    switch target.mode {
                    case .item:
                        itemCount += FileManager.default.fileExists(atPath: url.path) ? 1 : 0
                    case .contents:
                        itemCount += directoryContents(at: url).count
                    }
                }
            }
        }

        return (itemCount, categories.contains(.trash))
    }

    private static func clean(url: URL, mode: CleanDriveTarget.Mode, emptiesTrash: Bool) throws {
        let urls = switch mode {
        case .item:
            [url]
        case .contents:
            directoryContents(at: url)
        }

        for itemURL in urls {
            guard FileManager.default.fileExists(atPath: itemURL.path) else {
                continue
            }

            if emptiesTrash {
                try FileManager.default.removeItem(at: itemURL)
            } else {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: itemURL, resultingItemURL: &resultingURL)
            }
        }
    }

    private static func resolvedURLs(for target: CleanDriveTarget) -> [URL] {
        let expandedPath = NSString(string: target.path).expandingTildeInPath
        let components = expandedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        var urls = [URL(fileURLWithPath: "/")]
        for component in components where !component.isEmpty {
            if component == "*" {
                urls = urls.flatMap { directoryContents(at: $0) }
            } else {
                urls = urls.map { $0.appendingPathComponent(component) }
            }
        }

        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func size(of url: URL, mode: CleanDriveTarget.Mode) -> UInt64 {
        switch mode {
        case .item:
            directorySize(at: url)
        case .contents:
            directoryContents(at: url).reduce(UInt64(0)) { $0 + directorySize(at: $1) }
        }
    }

    private static func directoryContents(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        )) ?? []
    }

    private static func directorySize(at url: URL) -> UInt64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        return enumerator.reduce(UInt64(0)) { partialResult, entry in
            guard let fileURL = entry as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                return partialResult
            }

            return partialResult + UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
    }
}

public struct CleanDriveResult: Sendable {
    public var cleanedBytes: UInt64
    public var failedPaths: [String]
}

public struct CleanDriveWindowView: View {
    var onQuit: () -> Void

    @State private var items: [CleanDriveItem] = []
    @State private var selectedCategories = Set(CleanDriveCategoryID.allCases.filter(\.defaultSelected))
    @State private var isScanning = true
    @State private var isCleaning = false
    @State private var message = "Scanning..."
    @State private var isShowingSettings = false
    private let layout = CleanDriveLayout.current

    public init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                VStack(spacing: layout.contentSpacing) {
                    summary
                    progressBar
                    categoryList
                    cleanButton
                    storageButton
                }
                .padding(.horizontal, layout.contentHorizontalPadding)
                .padding(.bottom, layout.contentBottomPadding)
            }

            if isShowingSettings {
                PreferencesOverlay(cornerRadius: 18) {
                    CleanDriveSettingsView(
                        onQuit: requestQuit,
                        onClose: { isShowingSettings = false }
                    )
                }
            }
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height)
        .frostedPanel(cornerRadius: 18)
        .task {
            await reload()
        }
    }

    private var header: some View {
        HStack {
            Button(action: requestQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: layout.closeIconSize, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.headerButtonSize, height: layout.headerButtonSize)
            }
            .buttonStyle(.plain)
            .help("Quit Clean Drive")

            Spacer()

            Text("Clean Drive")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: layout.settingsIconSize, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.headerButtonSize, height: layout.headerButtonSize)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, layout.headerHorizontalPadding)
        .padding(.top, layout.headerTopPadding)
        .padding(.bottom, layout.headerBottomPadding)
    }

    private var summary: some View {
        VStack(spacing: layout.summarySpacing) {
            Text(selectedSize.diskBytesString)
                .font(.system(size: layout.summaryValueFontSize, weight: .light, design: .rounded))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(message)
                .font(.system(size: layout.summaryLabelFontSize, weight: .bold))
                .foregroundStyle(.primary.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, layout.summaryTopPadding)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: layout.progressCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))

                RoundedRectangle(cornerRadius: layout.progressCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: layout.progressHeight)
        .overlay {
            RoundedRectangle(cornerRadius: layout.progressCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var categoryList: some View {
        VStack(spacing: layout.rowSpacing) {
            ForEach(items) { item in
                Button {
                    toggle(item.id)
                } label: {
                    HStack(spacing: layout.rowHorizontalSpacing) {
                        CleanDriveCheckbox(
                            isSelected: selectedCategories.contains(item.id),
                            tint: item.id.tint,
                            size: layout.checkboxSize,
                            checkmarkFontSize: layout.checkmarkFontSize
                        )

                        Text(item.title)
                            .font(.system(size: layout.rowTitleFontSize, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(item.size.diskBytesString)
                            .font(.system(size: layout.rowValueFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isScanning ? 0.6 : 1)
    }

    private var cleanButton: some View {
        Button {
            confirmAndClean()
        } label: {
            Text(isCleaning ? "Cleaning..." : "Clean Up")
                .font(.system(size: layout.cleanButtonFontSize, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, layout.cleanButtonHorizontalPadding)
                .frame(height: layout.cleanButtonHeight)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: layout.buttonCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: layout.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedSize == 0 || isScanning || isCleaning)
        .opacity(selectedSize == 0 || isScanning || isCleaning ? 0.45 : 1)
        .padding(.top, layout.cleanButtonTopPadding)
    }

    private var storageButton: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
        } label: {
            Text("Manage Storage...")
                .font(.system(size: layout.storageFontSize, weight: .medium))
                .underline()
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var selectedSize: UInt64 {
        items
            .filter { selectedCategories.contains($0.id) }
            .reduce(UInt64(0)) { $0 + $1.size }
    }

    private var totalSize: UInt64 {
        max(items.reduce(UInt64(0)) { $0 + $1.size }, 1)
    }

    private var progressFraction: Double {
        guard !items.isEmpty else {
            return 0
        }

        return max(0.04, min(Double(selectedSize) / Double(totalSize), 1))
    }

    private func toggle(_ id: CleanDriveCategoryID) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }

        updateMessage()
    }

    private func updateMessage() {
        message = selectedSize > 0 ? "Ready for Cleanup" : "Nothing Selected"
    }

    private func reload() async {
        isScanning = true
        message = "Scanning..."
        let scannedItems = await Task.detached(priority: .userInitiated) {
            CleanDriveScanner.scan()
        }.value
        items = scannedItems
        isScanning = false
        updateMessage()
    }

    private func confirmAndClean() {
        let summary = CleanDriveScanner.targetSummary(for: selectedCategories)
        let alert = NSAlert()
        alert.messageText = "Clean selected items?"
        alert.informativeText = "Selected cache, log, and temp items will be moved to Trash where possible. \(summary.itemCount) visible and hidden items are currently targeted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clean Up")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        if summary.includesTrash {
            let trashAlert = NSAlert()
            trashAlert.messageText = "Permanently empty Trash?"
            trashAlert.informativeText = "Trash contents cannot be moved to Trash again, so these items will be permanently removed."
            trashAlert.alertStyle = .critical
            trashAlert.addButton(withTitle: "Empty Trash")
            trashAlert.addButton(withTitle: "Cancel")

            guard trashAlert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        isCleaning = true
        message = "Cleaning..."
        let selected = selectedCategories

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CleanDriveScanner.clean(categories: selected)
            }.value

            await reload()
            isCleaning = false
            message = result.failedPaths.isEmpty
                ? "Cleaned \(result.cleanedBytes.diskBytesString)"
                : "Cleaned with \(result.failedPaths.count) skipped"
        }
    }

    private func requestQuit() {
        guard !isCleaning else {
            let alert = NSAlert()
            alert.messageText = "Clean Drive is still cleaning"
            alert.informativeText = "Wait for cleanup to finish before quitting so file operations are not interrupted."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        onQuit()
    }
}

private struct CleanDriveCheckbox: View {
    var isSelected: Bool
    var tint: Color
    var size: CGFloat
    var checkmarkFontSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isSelected ? tint : Color.secondary.opacity(0.28))
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: checkmarkFontSize, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
            }
    }
}

private struct CleanDriveLayout {
    let scale: CGFloat

    static var current: CleanDriveLayout {
        CleanDriveLayout(scale: CleanDriveSizing.currentScale)
    }

    var windowSize: NSSize { CleanDriveSizing.preferredSize() }
    var contentSpacing: CGFloat { 18 * scale }
    var contentHorizontalPadding: CGFloat { 40 * scale }
    var contentBottomPadding: CGFloat { 26 * scale }
    var headerButtonSize: CGFloat { 32 * scale }
    var closeIconSize: CGFloat { 18 * scale }
    var settingsIconSize: CGFloat { 20 * scale }
    var titleFontSize: CGFloat { 27 * scale }
    var headerHorizontalPadding: CGFloat { 24 * scale }
    var headerTopPadding: CGFloat { 18 * scale }
    var headerBottomPadding: CGFloat { 12 * scale }
    var summarySpacing: CGFloat { 8 * scale }
    var summaryValueFontSize: CGFloat { 56 * scale }
    var summaryLabelFontSize: CGFloat { 20 * scale }
    var summaryTopPadding: CGFloat { 12 * scale }
    var progressHeight: CGFloat { 24 * scale }
    var progressCornerRadius: CGFloat { 4 * scale }
    var rowSpacing: CGFloat { 12 * scale }
    var rowHorizontalSpacing: CGFloat { 14 * scale }
    var checkboxSize: CGFloat { 24 * scale }
    var checkmarkFontSize: CGFloat { 15 * scale }
    var rowTitleFontSize: CGFloat { 19 * scale }
    var rowValueFontSize: CGFloat { 17 * scale }
    var cleanButtonFontSize: CGFloat { 18 * scale }
    var cleanButtonHorizontalPadding: CGFloat { 22 * scale }
    var cleanButtonHeight: CGFloat { 36 * scale }
    var cleanButtonTopPadding: CGFloat { 4 * scale }
    var buttonCornerRadius: CGFloat { 8 * scale }
    var storageFontSize: CGFloat { 17 * scale }
}

private struct CleanDriveSettingsView: View {
    var onQuit: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Clean Drive Settings")
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }

            Text("Quit closes Clean Drive. You can launch it again from D'Monte's Toolbox.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                onClose()
                onQuit()
            } label: {
                Label("Quit Clean Drive", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 330, height: 190)
    }
}

private struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            GreenSwitch(isOn: $isOn)
        }
    }
}
