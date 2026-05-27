import AppKit
import Foundation
import os
import SwiftUI

public struct DiskVolume: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let isRemovable: Bool
    public let isInternal: Bool

    public var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }
}

public enum DiskVolumeProvider {
    public static func mountedVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsBrowsableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeIsLocalKey,
            .volumeURLForRemountingKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }

        let volumes: [DiskVolume] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                return nil
            }

            guard values.volumeIsBrowsable == true, values.volumeIsLocal == true else {
                return nil
            }

            let total = UInt64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else {
                return nil
            }

            let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
            let name = values.volumeName ?? url.lastPathComponent
            let isRemovable = (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false)
            let isInternal = values.volumeIsInternal ?? false

            return DiskVolume(
                url: url,
                name: name,
                totalBytes: total,
                freeBytes: free,
                isRemovable: isRemovable,
                isInternal: isInternal
            )
        }

        return volumes.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal {
                return lhs.isInternal && !rhs.isInternal
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public final class DiskNode: Identifiable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: UInt64
    public let children: [DiskNode]

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    public init(path: String, name: String, isDirectory: Bool, size: UInt64, children: [DiskNode]) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
    }

    public var fileExtension: String {
        if isDirectory { return "" }
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
}

public struct DiskScanProgress: Sendable {
    public let bytesScanned: UInt64
    public let itemsScanned: Int
    public let currentPath: String

    public static let empty = DiskScanProgress(bytesScanned: 0, itemsScanned: 0, currentPath: "")
}

public final class DiskScanProgressTracker: Sendable {
    private struct State {
        var bytes: UInt64 = 0
        var items: Int = 0
        var path: String = ""
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init() {}

    public var snapshot: DiskScanProgress {
        state.withLock {
            DiskScanProgress(bytesScanned: $0.bytes, itemsScanned: $0.items, currentPath: $0.path)
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    func add(bytes: UInt64) {
        state.withLock {
            $0.bytes &+= bytes
            $0.items += 1
        }
    }

    func setCurrentPath(_ path: String) {
        state.withLock { $0.path = path }
    }
}

private enum DiskSkipList {
    private static let skipped: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/.vol",
        "/cores",
        "/private/var/db",
        "/private/var/folders",
        "/private/var/vm",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/.DocumentRevisions-V100",
        "/.TemporaryItems",
        "/.Trashes"
    ]

    static func shouldSkip(_ path: String) -> Bool {
        skipped.contains(path)
    }
}

public enum DiskScanner {
    private static let parallelDepth = 2

    public static func scan(volume: DiskVolume, tracker: DiskScanProgressTracker? = nil) async -> DiskNode? {
        tracker?.reset()
        return await scanRoot(path: volume.url.path, name: volume.name, tracker: tracker)
    }

    public static func scan(at url: URL, tracker: DiskScanProgressTracker? = nil) async -> DiskNode? {
        tracker?.reset()
        let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
        return await scanRoot(path: url.path, name: displayName, tracker: tracker)
    }

    private static func scanRoot(path: String, name: String, tracker: DiskScanProgressTracker?) async -> DiskNode? {
        guard let rootResult = BulkDirectoryReader.read(at: path) else {
            return nil
        }

        var allowed: Set<DiskFilesystemID> = [rootResult.fsid]
        if path == "/", let dataFsid = fsid(of: "/System/Volumes/Data") {
            allowed.insert(dataFsid)
        }

        return await scan(
            path: path,
            name: name,
            depth: 0,
            allowedFsids: allowed,
            preread: rootResult,
            tracker: tracker
        )
    }

    private static func fsid(of path: String) -> DiskFilesystemID? {
        let fd = path.withCString { open($0, O_RDONLY | O_DIRECTORY, 0) }
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var sf = statfs()
        guard fstatfs(fd, &sf) == 0 else { return nil }
        return DiskFilesystemID(sf.f_fsid)
    }

    private static func joinPath(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    private static func scan(
        path: String,
        name: String,
        depth: Int,
        allowedFsids: Set<DiskFilesystemID>,
        preread: BulkDirectoryResult?,
        tracker: DiskScanProgressTracker?
    ) async -> DiskNode? {
        if Task.isCancelled || DiskSkipList.shouldSkip(path) {
            return nil
        }

        tracker?.setCurrentPath(path)

        let result: BulkDirectoryResult
        if let preread {
            result = preread
        } else if let r = BulkDirectoryReader.read(at: path) {
            result = r
        } else {
            return DiskNode(path: path, name: name, isDirectory: true, size: 0, children: [])
        }

        var children: [DiskNode] = []
        var totalSize: UInt64 = 0

        for entry in result.entries where !entry.isDirectory && !entry.isSymlink {
            if !allowedFsids.contains(entry.fsid) {
                continue
            }
            if entry.allocatedSize > 0 {
                let childPath = joinPath(path, entry.name)
                children.append(DiskNode(
                    path: childPath,
                    name: entry.name,
                    isDirectory: false,
                    size: entry.allocatedSize,
                    children: []
                ))
                totalSize &+= entry.allocatedSize
                tracker?.add(bytes: entry.allocatedSize)
            }
        }

        let directories = result.entries.filter {
            $0.isDirectory && !$0.isSymlink && allowedFsids.contains($0.fsid)
        }

        if depth < parallelDepth {
            let subnodes = await withTaskGroup(of: DiskNode?.self) { group in
                for dir in directories {
                    let childPath = joinPath(path, dir.name)
                    let childName = dir.name
                    let childDepth = depth + 1
                    group.addTask(priority: .userInitiated) {
                        await scan(
                            path: childPath,
                            name: childName,
                            depth: childDepth,
                            allowedFsids: allowedFsids,
                            preread: nil,
                            tracker: tracker
                        )
                    }
                }

                var collected: [DiskNode] = []
                for await sub in group {
                    if let node = sub {
                        collected.append(node)
                    }
                }
                return collected
            }

            for node in subnodes {
                children.append(node)
                totalSize &+= node.size
            }
        } else {
            for dir in directories {
                if Task.isCancelled {
                    return nil
                }

                let childPath = joinPath(path, dir.name)
                if let node = scanSerial(path: childPath, name: dir.name, allowedFsids: allowedFsids, tracker: tracker) {
                    children.append(node)
                    totalSize &+= node.size
                }
            }
        }

        let sorted = children.sorted { $0.size > $1.size }
        return DiskNode(path: path, name: name, isDirectory: true, size: totalSize, children: sorted)
    }

    private static func scanSerial(
        path: String,
        name: String,
        allowedFsids: Set<DiskFilesystemID>,
        tracker: DiskScanProgressTracker?
    ) -> DiskNode? {
        if Task.isCancelled || DiskSkipList.shouldSkip(path) {
            return nil
        }

        tracker?.setCurrentPath(path)

        guard let result = BulkDirectoryReader.read(at: path) else {
            return DiskNode(path: path, name: name, isDirectory: true, size: 0, children: [])
        }

        var children: [DiskNode] = []
        var totalSize: UInt64 = 0

        for entry in result.entries {
            if entry.isSymlink || !allowedFsids.contains(entry.fsid) {
                continue
            }

            let childPath = joinPath(path, entry.name)

            if entry.isDirectory {
                if let node = scanSerial(path: childPath, name: entry.name, allowedFsids: allowedFsids, tracker: tracker) {
                    children.append(node)
                    totalSize &+= node.size
                }
            } else if entry.allocatedSize > 0 {
                children.append(DiskNode(
                    path: childPath,
                    name: entry.name,
                    isDirectory: false,
                    size: entry.allocatedSize,
                    children: []
                ))
                totalSize &+= entry.allocatedSize
                tracker?.add(bytes: entry.allocatedSize)
            }
        }

        let sorted = children.sorted { $0.size > $1.size }
        return DiskNode(path: path, name: name, isDirectory: true, size: totalSize, children: sorted)
    }
}

public struct TreemapRect: Identifiable, Sendable {
    public let node: DiskNode
    public let rect: CGRect

    public var id: ObjectIdentifier { node.id }

    public init(node: DiskNode, rect: CGRect) {
        self.node = node
        self.rect = rect
    }
}

public enum TreemapLayout {
    public static func compute(nodes: [DiskNode], in bounds: CGRect, maxItems: Int = 200) -> [TreemapRect] {
        let positiveSized = nodes.filter { $0.size > 0 }
        guard !positiveSized.isEmpty, bounds.width > 1, bounds.height > 1 else {
            return []
        }

        let limited = Array(positiveSized.prefix(maxItems))
        let totalNodeSize = limited.reduce(UInt64(0)) { $0 + $1.size }
        guard totalNodeSize > 0 else {
            return []
        }

        let areaScale = Double(bounds.width) * Double(bounds.height) / Double(totalNodeSize)
        let weighted = limited.map { (node: $0, area: Double($0.size) * areaScale) }
        var results: [TreemapRect] = []
        squarify(items: weighted, bounds: bounds, results: &results)
        return results
    }

    private static func squarify(items: [(node: DiskNode, area: Double)], bounds: CGRect, results: inout [TreemapRect]) {
        if items.isEmpty || bounds.width < 1 || bounds.height < 1 {
            return
        }

        var remaining = items
        var current = bounds
        var row: [(node: DiskNode, area: Double)] = []
        var rowSide = min(current.width, current.height)

        while let head = remaining.first {
            let candidate = row + [head]
            if row.isEmpty || worst(row: candidate, side: rowSide) <= worst(row: row, side: rowSide) {
                row = candidate
                remaining.removeFirst()
            } else {
                layoutRow(row: row, in: &current, results: &results)
                row = []
                rowSide = min(current.width, current.height)
            }
        }

        if !row.isEmpty {
            layoutRow(row: row, in: &current, results: &results)
        }
    }

    private static func worst(row: [(node: DiskNode, area: Double)], side: CGFloat) -> Double {
        guard !row.isEmpty, side > 0 else {
            return .greatestFiniteMagnitude
        }

        let total = row.reduce(0.0) { $0 + $1.area }
        guard total > 0 else {
            return .greatestFiniteMagnitude
        }

        let minArea = row.map(\.area).min() ?? total
        let maxArea = row.map(\.area).max() ?? total
        let sideSquared = Double(side * side)
        let totalSquared = total * total
        return max(sideSquared * maxArea / totalSquared, totalSquared / (sideSquared * minArea))
    }

    private static func layoutRow(row: [(node: DiskNode, area: Double)], in bounds: inout CGRect, results: inout [TreemapRect]) {
        let totalArea = row.reduce(0.0) { $0 + $1.area }
        guard totalArea > 0, bounds.width > 0.5, bounds.height > 0.5 else {
            return
        }

        if bounds.width >= bounds.height {
            let rowWidth = CGFloat(totalArea / Double(bounds.height))
            var y = bounds.minY
            for entry in row {
                let h = CGFloat(entry.area / Double(rowWidth))
                let rect = CGRect(x: bounds.minX, y: y, width: rowWidth, height: h)
                results.append(TreemapRect(node: entry.node, rect: rect))
                y += h
            }
            bounds = CGRect(x: bounds.minX + rowWidth, y: bounds.minY, width: max(0, bounds.width - rowWidth), height: bounds.height)
        } else {
            let rowHeight = CGFloat(totalArea / Double(bounds.width))
            var x = bounds.minX
            for entry in row {
                let w = CGFloat(entry.area / Double(rowHeight))
                let rect = CGRect(x: x, y: bounds.minY, width: w, height: rowHeight)
                results.append(TreemapRect(node: entry.node, rect: rect))
                x += w
            }
            bounds = CGRect(x: bounds.minX, y: bounds.minY + rowHeight, width: bounds.width, height: max(0, bounds.height - rowHeight))
        }
    }
}

public enum DiskItemPalette {
    private static let filePalette: [Color] = [
        Color(red: 0.95, green: 0.55, blue: 0.30),
        Color(red: 0.40, green: 0.72, blue: 0.95),
        Color(red: 0.86, green: 0.40, blue: 0.62),
        Color(red: 0.40, green: 0.82, blue: 0.62),
        Color(red: 0.96, green: 0.78, blue: 0.30),
        Color(red: 0.60, green: 0.48, blue: 0.92),
        Color(red: 0.92, green: 0.45, blue: 0.45),
        Color(red: 0.36, green: 0.88, blue: 0.84),
        Color(red: 0.78, green: 0.86, blue: 0.34),
        Color(red: 0.55, green: 0.62, blue: 0.92),
        Color(red: 0.92, green: 0.62, blue: 0.84),
        Color(red: 0.45, green: 0.84, blue: 0.42),
        Color(red: 0.74, green: 0.66, blue: 0.50),
        Color(red: 0.42, green: 0.58, blue: 0.74)
    ]

    private static let directoryPalette: [Color] = [
        Color(red: 0.32, green: 0.52, blue: 0.78),
        Color(red: 0.58, green: 0.38, blue: 0.72),
        Color(red: 0.78, green: 0.46, blue: 0.34),
        Color(red: 0.30, green: 0.62, blue: 0.56),
        Color(red: 0.74, green: 0.36, blue: 0.50),
        Color(red: 0.48, green: 0.60, blue: 0.32),
        Color(red: 0.78, green: 0.64, blue: 0.30),
        Color(red: 0.42, green: 0.48, blue: 0.76),
        Color(red: 0.62, green: 0.42, blue: 0.76),
        Color(red: 0.30, green: 0.66, blue: 0.74),
        Color(red: 0.74, green: 0.40, blue: 0.40),
        Color(red: 0.56, green: 0.54, blue: 0.40)
    ]

    public static func color(for node: DiskNode) -> Color {
        let key = node.isDirectory
            ? node.name
            : (node.fileExtension.isEmpty ? node.name : node.fileExtension)

        let hash = key.unicodeScalars.reduce(UInt32(2_166_136_261)) { partial, scalar in
            (partial ^ scalar.value) &* 16_777_619
        }

        let table = node.isDirectory ? directoryPalette : filePalette
        return table[Int(hash % UInt32(table.count))]
    }
}

public struct DiskAnalyzerWindowView: View {
    var onQuit: () -> Void

    @State private var volumes: [DiskVolume] = []
    @State private var selectedVolume: DiskVolume?
    @State private var pathStack: [DiskNode] = []
    @State private var scanCache: [String: DiskNode] = [:]
    @State private var isScanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var scanTracker: DiskScanProgressTracker?
    @State private var hoveredNode: DiskNode?
    @State private var isShowingSettings = false

    private let layout = DiskAnalyzerLayout.current

    public init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                VStack(spacing: layout.sectionSpacing) {
                    volumeStrip
                    summaryPanel
                    breadcrumbBar
                    treemap
                }
                .padding(.horizontal, layout.contentHorizontalPadding)
                .padding(.bottom, layout.contentBottomPadding)
            }

            if isShowingSettings {
                PreferencesOverlay(cornerRadius: 18) {
                    DiskAnalyzerSettingsView(
                        onQuit: requestQuit,
                        onClose: { isShowingSettings = false }
                    )
                }
            }
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height)
        .frostedPanel(cornerRadius: 18)
        .task {
            refreshVolumes(autoSelectFirst: true)
        }
        .onDisappear {
            scanTask?.cancel()
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
            .help("Quit Disk Usage Analyzer")

            Spacer()

            Text("Disk Usage Analyzer")
                .font(.system(size: layout.titleFontSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))

            Spacer()

            HStack(spacing: layout.headerButtonSpacing) {
                Button(action: rescan) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: layout.headerIconSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: layout.headerButtonSize, height: layout.headerButtonSize)
                }
                .buttonStyle(.plain)
                .help("Rescan")
                .disabled(selectedVolume == nil || isScanning)
                .opacity(selectedVolume == nil || isScanning ? 0.45 : 1)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: layout.headerIconSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: layout.headerButtonSize, height: layout.headerButtonSize)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, layout.headerHorizontalPadding)
        .padding(.top, layout.headerTopPadding)
        .padding(.bottom, layout.headerBottomPadding)
    }

    private var volumeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: layout.volumeChipSpacing) {
                ForEach(volumes) { volume in
                    VolumeChip(
                        volume: volume,
                        isSelected: selectedVolume?.id == volume.id,
                        layout: layout
                    ) {
                        select(volume: volume)
                    }
                }

                Button(action: { refreshVolumes(autoSelectFirst: false) }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: layout.volumeChipIconSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: layout.volumeChipHeight, height: layout.volumeChipHeight)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: layout.volumeChipCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Refresh volume list")
            }
            .padding(.horizontal, 2)
        }
        .frame(height: layout.volumeChipHeight + 4)
    }

    private var summaryPanel: some View {
        Group {
            if isScanning, let tracker = scanTracker {
                ScanProgressPanel(
                    tracker: tracker,
                    volume: selectedVolume,
                    layout: layout
                )
            } else {
                idleSummaryPanel
            }
        }
    }

    private var idleSummaryPanel: some View {
        VStack(alignment: .leading, spacing: layout.summarySpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(usedLabel)
                    .font(.system(size: layout.summaryValueFontSize, weight: .light, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("used of \(totalLabel)")
                    .font(.system(size: layout.summarySubFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(freeLabel) free")
                    .font(.system(size: layout.summarySubFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.20))
                    .frame(height: layout.summaryBarHeight)

                GeometryReader { proxy in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.66, blue: 0.96), Color(red: 0.62, green: 0.46, blue: 0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * usedFraction)
                }
                .frame(height: layout.summaryBarHeight)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: layout.breadcrumbSpacing) {
            Button(action: goUp) {
                Image(systemName: "chevron.left")
                    .font(.system(size: layout.breadcrumbIconSize, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.breadcrumbButtonSize, height: layout.breadcrumbButtonSize)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(pathStack.count <= 1)
            .opacity(pathStack.count <= 1 ? 0.4 : 1)
            .help("Back")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(pathStack.enumerated()), id: \.element.id) { index, node in
                        Button(action: { navigate(toIndex: index) }) {
                            Text(node.name)
                                .font(.system(size: layout.breadcrumbFontSize, weight: .semibold))
                                .foregroundStyle(index == pathStack.count - 1 ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        if index < pathStack.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: layout.breadcrumbFontSize - 2, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: layout.breadcrumbHeight)
    }

    private var treemap: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let rects = currentNode.map { TreemapLayout.compute(nodes: $0.children, in: bounds) } ?? []

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: layout.treemapCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))

                if isScanning && rects.isEmpty {
                    centeredOverlay { ScanningView(layout: layout) }
                } else if rects.isEmpty {
                    centeredOverlay { EmptyTreemapView(layout: layout) }
                } else {
                    ZStack(alignment: .topLeading) {
                        ForEach(rects) { entry in
                            TreemapTile(
                                entry: entry,
                                isHovered: hoveredNode?.id == entry.node.id,
                                layout: layout
                            )
                            .frame(width: max(0, entry.rect.width), height: max(0, entry.rect.height), alignment: .topLeading)
                            .offset(x: entry.rect.minX, y: entry.rect.minY)
                            .onHover { hovering in
                                if hovering {
                                    hoveredNode = entry.node
                                } else if hoveredNode?.id == entry.node.id {
                                    hoveredNode = nil
                                }
                            }
                            .onTapGesture(count: 2) { revealInFinder(node: entry.node) }
                            .onTapGesture { handleTap(node: entry.node) }
                            .help(tooltip(for: entry.node))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }

                if let hoveredNode {
                    HoverChip(node: hoveredNode, layout: layout)
                        .padding(layout.treemapInnerPadding)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: layout.treemapCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: layout.treemapCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centeredOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentNode: DiskNode? {
        pathStack.last
    }

    private var usedFraction: CGFloat {
        guard let selectedVolume, selectedVolume.totalBytes > 0 else { return 0 }
        return max(0.03, min(CGFloat(Double(selectedVolume.usedBytes) / Double(selectedVolume.totalBytes)), 1))
    }

    private var usedLabel: String {
        selectedVolume?.usedBytes.diskBytesString ?? "—"
    }

    private var totalLabel: String {
        selectedVolume?.totalBytes.diskBytesString ?? "—"
    }

    private var freeLabel: String {
        selectedVolume?.freeBytes.diskBytesString ?? "—"
    }

    private func tooltip(for node: DiskNode) -> String {
        "\(node.name) — \(node.size.diskBytesString)"
    }

    private func refreshVolumes(autoSelectFirst: Bool) {
        let detected = DiskVolumeProvider.mountedVolumes()
        volumes = detected

        let detectedIds = Set(detected.map(\.id))
        for cachedId in scanCache.keys where !detectedIds.contains(cachedId) {
            scanCache.removeValue(forKey: cachedId)
        }

        if let selectedVolume, !detected.contains(where: { $0.id == selectedVolume.id }) {
            scanTask?.cancel()
            scanTask = nil
            self.selectedVolume = nil
            pathStack = []
            scanTracker = nil
            isScanning = false
            hoveredNode = nil
        }

        if autoSelectFirst, selectedVolume == nil, let first = detected.first {
            select(volume: first)
        }
    }

    private func select(volume: DiskVolume) {
        scanTask?.cancel()
        scanTask = nil
        scanTracker = nil
        isScanning = false
        hoveredNode = nil
        selectedVolume = volume

        if let cached = scanCache[volume.id] {
            pathStack = [cached]
            return
        }

        pathStack = []
        startScan(volume: volume)
    }

    private func rescan() {
        guard let selectedVolume else { return }
        scanCache.removeValue(forKey: selectedVolume.id)
        pathStack = []
        startScan(volume: selectedVolume)
    }

    private func startScan(volume: DiskVolume) {
        scanTask?.cancel()
        isScanning = true
        hoveredNode = nil

        let tracker = DiskScanProgressTracker()
        scanTracker = tracker
        let volumeId = volume.id

        scanTask = Task(priority: .userInitiated) {
            let node = await DiskScanner.scan(volume: volume, tracker: tracker)

            if Task.isCancelled {
                return
            }

            await MainActor.run {
                if let node {
                    scanCache[volumeId] = node
                }
                if selectedVolume?.id == volumeId {
                    pathStack = node.map { [$0] } ?? []
                }
                isScanning = false
                scanTracker = nil
            }
        }
    }

    private func handleTap(node: DiskNode) {
        guard node.isDirectory, !node.children.isEmpty else {
            return
        }

        pathStack.append(node)
        hoveredNode = nil
    }

    private func goUp() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        hoveredNode = nil
    }

    private func navigate(toIndex index: Int) {
        guard index < pathStack.count else { return }
        pathStack = Array(pathStack.prefix(index + 1))
        hoveredNode = nil
    }

    private func revealInFinder(node: DiskNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    private func requestQuit() {
        scanTask?.cancel()
        onQuit()
    }
}

private struct VolumeChip: View {
    var volume: DiskVolume
    var isSelected: Bool
    var layout: DiskAnalyzerLayout
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: layout.volumeChipIconSize, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : volume.isRemovable ? .orange : .accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.name)
                        .font(.system(size: layout.volumeChipFontSize, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text("\(volume.usedBytes.diskBytesString) / \(volume.totalBytes.diskBytesString)")
                        .font(.system(size: layout.volumeChipSubFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, layout.volumeChipHorizontalPadding)
            .frame(height: layout.volumeChipHeight)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: layout.volumeChipCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: layout.volumeChipCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.32 : 0.16), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        if volume.isRemovable {
            return "externaldrive.fill.badge.plus"
        }
        return volume.isInternal ? "internaldrive.fill" : "externaldrive.fill"
    }
}

private struct TreemapTile: View {
    var entry: TreemapRect
    var isHovered: Bool
    var layout: DiskAnalyzerLayout

    var body: some View {
        let color = DiskItemPalette.color(for: entry.node)
        let showLabel = entry.rect.width >= layout.tileLabelMinSide && entry.rect.height >= layout.tileLabelMinSide

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(isHovered ? 0.96 : 0.86))

            if showLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.node.name)
                        .font(.system(size: layout.tileLabelFontSize, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)

                    if entry.rect.height >= layout.tileLabelMinSide * 1.6 {
                        Text(entry.node.size.diskBytesString)
                            .font(.system(size: layout.tileLabelFontSize - 1, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
        }
        .overlay {
            if isHovered {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct HoverChip: View {
    var node: DiskNode
    var layout: DiskAnalyzerLayout

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: layout.hoverChipIconSize, weight: .semibold))
                .foregroundStyle(.white)

            Text(node.name)
                .font(.system(size: layout.hoverChipFontSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(node.size.diskBytesString)
                .font(.system(size: layout.hoverChipFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

private struct ScanningView: View {
    var layout: DiskAnalyzerLayout

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning...")
                .font(.system(size: layout.emptyFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanProgressPanel: View {
    var tracker: DiskScanProgressTracker
    var volume: DiskVolume?
    var layout: DiskAnalyzerLayout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let progress = tracker.snapshot
            let target = max(volume?.usedBytes ?? 0, 1)
            let fraction = min(1.0, max(0.02, Double(progress.bytesScanned) / Double(target)))

            VStack(alignment: .leading, spacing: layout.summarySpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(progress.bytesScanned.diskBytesString)
                        .font(.system(size: layout.summaryValueFontSize, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("scanned · \(progress.itemsScanned.formatted()) items")
                        .font(.system(size: layout.summarySubFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let volume {
                        Text("of \(volume.usedBytes.diskBytesString)")
                            .font(.system(size: layout.summarySubFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.20))
                        .frame(height: layout.summaryBarHeight)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.42, green: 0.66, blue: 0.96), Color(red: 0.62, green: 0.46, blue: 0.92)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(fraction))
                            .animation(.easeOut(duration: 0.18), value: fraction)
                    }
                    .frame(height: layout.summaryBarHeight)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: layout.summarySubFontSize - 1, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(displayPath(progress.currentPath))
                        .font(.system(size: layout.summarySubFontSize - 1, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func displayPath(_ path: String) -> String {
        if path.isEmpty {
            return "Preparing scan..."
        }
        return path
    }
}

private struct EmptyTreemapView: View {
    var layout: DiskAnalyzerLayout

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.system(size: layout.emptyIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Select a volume to view its usage")
                .font(.system(size: layout.emptyFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct DiskAnalyzerSettingsView: View {
    var onQuit: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Disk Analyzer Settings")
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

            Text("Click a block to drill into a folder. Double-click reveals it in Finder. External drives appear automatically when mounted.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                onClose()
                onQuit()
            } label: {
                Label("Quit Disk Usage Analyzer", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 220)
    }
}

private struct DiskAnalyzerLayout {
    let scale: CGFloat

    static var current: DiskAnalyzerLayout {
        DiskAnalyzerLayout(scale: DiskAnalyzerSizing.currentScale)
    }

    var windowSize: NSSize { DiskAnalyzerSizing.preferredSize() }
    var sectionSpacing: CGFloat { 14 * scale }
    var contentHorizontalPadding: CGFloat { 22 * scale }
    var contentBottomPadding: CGFloat { 22 * scale }

    var headerButtonSize: CGFloat { 32 * scale }
    var headerButtonSpacing: CGFloat { 4 * scale }
    var closeIconSize: CGFloat { 18 * scale }
    var headerIconSize: CGFloat { 16 * scale }
    var titleFontSize: CGFloat { 22 * scale }
    var headerHorizontalPadding: CGFloat { 20 * scale }
    var headerTopPadding: CGFloat { 16 * scale }
    var headerBottomPadding: CGFloat { 10 * scale }

    var volumeChipSpacing: CGFloat { 8 * scale }
    var volumeChipHeight: CGFloat { 44 * scale }
    var volumeChipHorizontalPadding: CGFloat { 12 * scale }
    var volumeChipCornerRadius: CGFloat { 10 * scale }
    var volumeChipIconSize: CGFloat { 14 * scale }
    var volumeChipFontSize: CGFloat { 12.5 * scale }
    var volumeChipSubFontSize: CGFloat { 10.5 * scale }

    var summarySpacing: CGFloat { 8 * scale }
    var summaryValueFontSize: CGFloat { 28 * scale }
    var summarySubFontSize: CGFloat { 13 * scale }
    var summaryBarHeight: CGFloat { 10 * scale }

    var breadcrumbHeight: CGFloat { 24 * scale }
    var breadcrumbSpacing: CGFloat { 8 * scale }
    var breadcrumbButtonSize: CGFloat { 22 * scale }
    var breadcrumbIconSize: CGFloat { 11 * scale }
    var breadcrumbFontSize: CGFloat { 13 * scale }

    var treemapCornerRadius: CGFloat { 10 * scale }
    var treemapInnerPadding: CGFloat { 10 * scale }
    var tileLabelFontSize: CGFloat { 11 * scale }
    var tileLabelMinSide: CGFloat { 56 * scale }
    var hoverChipIconSize: CGFloat { 11 * scale }
    var hoverChipFontSize: CGFloat { 12 * scale }
    var emptyIconSize: CGFloat { 38 * scale }
    var emptyFontSize: CGFloat { 14 * scale }
}
