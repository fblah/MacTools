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
    public let directoriesScanned: Int
    public let directoriesDiscovered: Int
    public let currentPath: String
    public let inaccessibleCount: Int

    public static let empty = DiskScanProgress(
        bytesScanned: 0,
        itemsScanned: 0,
        directoriesScanned: 0,
        directoriesDiscovered: 0,
        currentPath: "",
        inaccessibleCount: 0
    )
}

public final class DiskScanProgressTracker: Sendable {
    private struct State {
        var bytes: UInt64 = 0
        var items: Int = 0
        var directories: Int = 0
        var directoriesDiscovered: Int = 0
        var path: String = ""
        var inaccessible: Int = 0
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init() {}

    public var snapshot: DiskScanProgress {
        state.withLock {
            DiskScanProgress(
                bytesScanned: $0.bytes,
                itemsScanned: $0.items,
                directoriesScanned: $0.directories,
                directoriesDiscovered: $0.directoriesDiscovered,
                currentPath: $0.path,
                inaccessibleCount: $0.inaccessible
            )
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

    func recordDirectory() {
        state.withLock {
            $0.directories += 1
            $0.directoriesDiscovered = max($0.directoriesDiscovered, $0.directories)
        }
    }

    func recordDiscoveredDirectories(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { $0.directoriesDiscovered += count }
    }

    func recordInaccessible() {
        state.withLock { $0.inaccessible += 1 }
    }
}

/// Cooperative pause/resume gate for a running scan. The scanner awaits
/// `waitWhilePaused()` at every directory; while paused all callers suspend and
/// resume together when `resume()` is called. Cancellation always wakes waiters
/// so a paused scan can still be torn down.
public final class ScanPauseGate: Sendable {
    private struct State {
        var paused = false
        var nextID = 0
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init() {}

    public var isPaused: Bool {
        state.withLock { $0.paused }
    }

    public func pause() {
        state.withLock { $0.paused = true }
    }

    public func resume() {
        drainWaiters(unpause: true).forEach { $0.resume() }
    }

    @discardableResult
    private func drainWaiters(unpause: Bool) -> [CheckedContinuation<Void, Never>] {
        state.withLock { state in
            if unpause { state.paused = false }
            let continuations = Array(state.waiters.values)
            state.waiters.removeAll()
            return continuations
        }
    }

    func waitWhilePaused() async {
        if Task.isCancelled { return }
        if !state.withLock({ $0.paused }) { return }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let waiterID: Int? = state.withLock { state in
                    guard state.paused else { return nil }
                    let id = state.nextID
                    state.nextID += 1
                    state.waiters[id] = continuation
                    return id
                }
                // No longer paused by the time we acquired the lock — proceed now.
                if waiterID == nil {
                    continuation.resume()
                }
            }
        } onCancel: {
            // Wake everyone so a cancelled scan never hangs on a paused gate.
            drainWaiters(unpause: false).forEach { $0.resume() }
        }
    }
}

public enum FullDiskAccess {
    /// Best-effort check for whether this app has been granted Full Disk Access.
    /// Probes a TCC-protected directory that exists on every Mac: without the grant
    /// the directory listing fails with EPERM; with it (or if the path is absent)
    /// we treat access as available.
    public static func isGranted() -> Bool {
        let probe = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC")
        guard FileManager.default.fileExists(atPath: probe) else {
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    public static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private enum DiskSkipList {
    // Only paths that would double-count the volume (firmlinked Data volume under
    // /System/Volumes), cross into other mounted volumes (/Volumes), or are virtual
    // filesystems that don't represent real on-disk bytes (/dev, /.vol). Everything
    // else — caches, swap (/private/var/vm), the Spotlight index, Trashes — is real
    // usage on this volume and is scanned so it shows up in the treemap.
    private static let skipped: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/.vol"
    ]

    static func shouldSkip(_ path: String) -> Bool {
        skipped.contains(path)
    }
}

public enum DiskScanner {
    private static let parallelDepth = 2

    static let unaccountedNodeName = "Unaccounted / Inaccessible"

    public static func scan(volume: DiskVolume, tracker: DiskScanProgressTracker? = nil, gate: ScanPauseGate? = nil) async -> DiskNode? {
        tracker?.reset()
        guard let root = await scanRoot(path: volume.url.path, name: volume.name, tracker: tracker, gate: gate) else {
            return nil
        }
        return reconciled(root: root, usedBytes: volume.usedBytes)
    }

    private static func reconciled(root: DiskNode, usedBytes: UInt64) -> DiskNode {
        guard usedBytes > root.size else { return root }
        let gap = usedBytes - root.size
        guard gap > usedBytes / 200 else { return root }

        let placeholder = DiskNode(
            path: root.path,
            name: unaccountedNodeName,
            isDirectory: false,
            size: gap,
            children: []
        )
        let children = (root.children + [placeholder]).sorted { $0.size > $1.size }
        return DiskNode(path: root.path, name: root.name, isDirectory: true, size: usedBytes, children: children)
    }

    public static func scan(at url: URL, tracker: DiskScanProgressTracker? = nil, gate: ScanPauseGate? = nil) async -> DiskNode? {
        tracker?.reset()
        let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
        return await scanRoot(path: url.path, name: displayName, tracker: tracker, gate: gate)
    }

    private static func scanRoot(path: String, name: String, tracker: DiskScanProgressTracker?, gate: ScanPauseGate?) async -> DiskNode? {
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
            tracker: tracker,
            gate: gate
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
        tracker: DiskScanProgressTracker?,
        gate: ScanPauseGate?
    ) async -> DiskNode? {
        if Task.isCancelled || DiskSkipList.shouldSkip(path) {
            return nil
        }

        await gate?.waitWhilePaused()
        if Task.isCancelled {
            return nil
        }

        tracker?.setCurrentPath(path)
        tracker?.recordDirectory()

        let result: BulkDirectoryResult
        if let preread {
            result = preread
        } else if let r = BulkDirectoryReader.read(at: path) {
            result = r
        } else {
            tracker?.recordInaccessible()
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

        let directories = result.entries.filter { entry in
            entry.isDirectory
                && !entry.isSymlink
                && allowedFsids.contains(entry.fsid)
                && !DiskSkipList.shouldSkip(joinPath(path, entry.name))
        }
        tracker?.recordDiscoveredDirectories(directories.count)

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
                            tracker: tracker,
                            gate: gate
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
                if let node = await scanSerial(path: childPath, name: dir.name, allowedFsids: allowedFsids, tracker: tracker, gate: gate) {
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
        tracker: DiskScanProgressTracker?,
        gate: ScanPauseGate?
    ) async -> DiskNode? {
        if Task.isCancelled || DiskSkipList.shouldSkip(path) {
            return nil
        }

        await gate?.waitWhilePaused()
        if Task.isCancelled {
            return nil
        }

        tracker?.setCurrentPath(path)
        tracker?.recordDirectory()

        guard let result = BulkDirectoryReader.read(at: path) else {
            tracker?.recordInaccessible()
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
                if DiskSkipList.shouldSkip(childPath) {
                    continue
                }
                tracker?.recordDiscoveredDirectories(1)
                if let node = await scanSerial(path: childPath, name: entry.name, allowedFsids: allowedFsids, tracker: tracker, gate: gate) {
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

struct DiskTreeCache {
    let root: DiskNode
    let pathByNodeID: [ObjectIdentifier: [DiskNode]]
    let nodeCount: Int

    init(root: DiskNode) {
        var paths: [ObjectIdentifier: [DiskNode]] = [:]
        var count = 0
        Self.index(node: root, path: [], paths: &paths, count: &count)
        self.root = root
        self.pathByNodeID = paths
        self.nodeCount = count
    }

    func path(to node: DiskNode) -> [DiskNode]? {
        pathByNodeID[node.id]
    }

    private static func index(
        node: DiskNode,
        path: [DiskNode],
        paths: inout [ObjectIdentifier: [DiskNode]],
        count: inout Int
    ) {
        count += 1
        let currentPath = path + [node]
        paths[node.id] = currentPath
        for child in node.children {
            index(node: child, path: currentPath, paths: &paths, count: &count)
        }
    }
}

private struct TreemapLayoutCacheKey: Hashable, Sendable {
    let nodeID: ObjectIdentifier
    let width: Int
    let height: Int

    init(node: DiskNode, size: CGSize) {
        self.nodeID = node.id
        self.width = max(0, Int(size.width.rounded()))
        self.height = max(0, Int(size.height.rounded()))
    }
}

private struct TreeScrollRequest: Equatable {
    let nodeID: ObjectIdentifier
    let generation: Int
}

private enum DiskTreemapLayoutCacheBuilder {
    static func build(root: DiskNode, size: CGSize) -> [TreemapLayoutCacheKey: [TreemapRect]] {
        guard size.width > 1, size.height > 1 else { return [:] }
        var cache: [TreemapLayoutCacheKey: [TreemapRect]] = [:]
        appendLayouts(for: root, size: size, cache: &cache)
        return cache
    }

    private static func appendLayouts(
        for node: DiskNode,
        size: CGSize,
        cache: inout [TreemapLayoutCacheKey: [TreemapRect]]
    ) {
        if Task.isCancelled { return }

        if !node.children.isEmpty {
            let bounds = CGRect(origin: .zero, size: size)
            cache[TreemapLayoutCacheKey(node: node, size: size)] = TreemapLayout.compute(nodes: node.children, in: bounds)
        }

        for child in node.children where child.isDirectory && !child.children.isEmpty {
            appendLayouts(for: child, size: size, cache: &cache)
        }
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
    @State private var treeCaches: [String: DiskTreeCache] = [:]
    @State private var treemapLayoutCaches: [String: [TreemapLayoutCacheKey: [TreemapRect]]] = [:]
    @State private var treemapLayoutTasks: [String: Task<Void, Never>] = [:]
    @State private var treemapSize: CGSize = .zero
    @State private var expandedTreeNodeIDs: Set<ObjectIdentifier> = []
    @State private var treeScrollRequest: TreeScrollRequest?
    @State private var treeScrollGeneration = 0
    @State private var scanTasks: [String: Task<Void, Never>] = [:]
    @State private var scanTrackers: [String: DiskScanProgressTracker] = [:]
    @State private var scanGenerations: [String: Int] = [:]
    @State private var scanGates: [String: ScanPauseGate] = [:]
    @State private var pausedVolumeIds: Set<String> = []
    @State private var hoveredNode: DiskNode?
    @State private var isShowingSettings = false
    @State private var fullDiskAccessGranted = true
    @State private var isFullScreen = false

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
                    if showsFullDiskAccessHint {
                        fullDiskAccessHint
                    }
                    analyzerContent
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
        .frame(
            minWidth: layout.minWindowSize.width,
            maxWidth: .infinity,
            minHeight: layout.minWindowSize.height,
            maxHeight: .infinity
        )
        .frostedPanel(cornerRadius: isFullScreen ? 0 : 18)
        .task {
            fullDiskAccessGranted = FullDiskAccess.isGranted()
            refreshVolumes(autoSelectFirst: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            // Return to a background (menu-bar-launched) app once we leave full screen.
            NSApp.setActivationPolicy(.accessory)
        }
        .onDisappear {
            for task in scanTasks.values {
                task.cancel()
            }
            for task in treemapLayoutTasks.values {
                task.cancel()
            }
        }
    }

    private func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let entering = !window.styleMask.contains(.fullScreen)
        if entering {
            // An accessory (LSUIElement) app can't reliably own a full-screen
            // space, so briefly become a regular app for the transition; we drop
            // back to accessory when full screen exits.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        window.toggleFullScreen(nil)
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

                Button(action: toggleFullScreen) {
                    Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: layout.headerIconSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: layout.headerButtonSize, height: layout.headerButtonSize)
                }
                .buttonStyle(.plain)
                .help(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")

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
                    layout: layout,
                    isPaused: isSelectedScanPaused,
                    onTogglePause: toggleScanPause
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

    private var fullDiskAccessHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: layout.breadcrumbFontSize, weight: .semibold))
                .foregroundStyle(.orange)

            Text(fullDiskAccessHintText)
                .font(.system(size: layout.breadcrumbFontSize - 1, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Open Settings", action: FullDiskAccess.openSettings)
                .buttonStyle(.plain)
                .font(.system(size: layout.breadcrumbFontSize - 1, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
        }
    }

    private var analyzerContent: some View {
        HStack(spacing: layout.analysisPaneSpacing) {
            treemap
                .layoutPriority(1)

            treePane
                .frame(width: layout.treePaneWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var treemap: some View {
        GeometryReader { proxy in
            let rects = currentNode.map { treemapRects(for: $0, size: proxy.size) } ?? []

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
                            .frame(width: max(0, entry.rect.width), height: max(0, entry.rect.height))
                            .onHover { hovering in
                                if hovering {
                                    hoveredNode = entry.node
                                } else if hoveredNode?.id == entry.node.id {
                                    hoveredNode = nil
                                }
                            }
                            .onTapGesture(count: 2) { revealInFinder(node: entry.node) }
                            .onTapGesture { handleTap(node: entry.node) }
                            .contextMenu {
                                Button {
                                    revealInFinder(node: entry.node)
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                            }
                            .help(tooltip(for: entry.node))
                            // Use .position (not .frame+.offset): offset moves only the
                            // rendering, leaving every tile's hit region stacked at the
                            // top-left, so hovering one tile highlighted another.
                            .position(x: entry.rect.midX, y: entry.rect.midY)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }

                if let hoveredNode {
                    VStack {
                        Spacer()
                        HoverChip(node: hoveredNode, layout: layout)
                            .padding(layout.treemapInnerPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: layout.treemapCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: layout.treemapCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .onAppear {
                updateTreemapSize(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateTreemapSize(newSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var treePane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: layout.treePaneCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.18))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: layout.treeHeaderIconSize, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Tree")
                        .font(.system(size: layout.treeHeaderFontSize, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.85))

                    Spacer(minLength: 0)

                    if let selectedTreeCache {
                        Text(selectedTreeCache.nodeCount.formatted())
                            .font(.system(size: layout.treeMetaFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, layout.treePanePadding)
                .padding(.vertical, layout.treeHeaderVerticalPadding)

                Divider()
                    .opacity(0.35)

                if let root = selectedTreeCache?.root {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                DiskTreeRow(
                                    node: root,
                                    depth: 0,
                                    expandedNodeIDs: expandedTreeNodeIDs,
                                    currentNodeID: currentNode?.id,
                                    highlightedNodeID: hoveredNode?.id,
                                    layout: layout,
                                    onToggleExpand: toggleTreeExpansion,
                                    onSelect: navigateFromTree,
                                    onReveal: revealInFinder
                                )
                            }
                            .padding(.vertical, 4)
                        }
                        .onChange(of: treeScrollRequest) { _, request in
                            guard let request else { return }
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    scrollProxy.scrollTo(request.nodeID, anchor: .center)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: layout.emptyIconSize * 0.68, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(isScanning ? "Building tree..." : "No scan yet")
                            .font(.system(size: layout.treeHeaderFontSize, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.treePaneCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: layout.treePaneCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func centeredOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isScanning: Bool {
        guard let id = selectedVolume?.id else { return false }
        return scanTasks[id] != nil
    }

    private var scanTracker: DiskScanProgressTracker? {
        guard let id = selectedVolume?.id else { return nil }
        return scanTrackers[id]
    }

    private var isSelectedScanPaused: Bool {
        guard let id = selectedVolume?.id else { return false }
        return pausedVolumeIds.contains(id)
    }

    // Full Disk Access only affects the boot volume — that's where the firmlinked
    // user-data folders (Mail, Messages, Photos, ~/Library) live. External and
    // other volumes have no TCC-protected paths, so we never nag about FDA there.
    private var selectedIsBootVolume: Bool {
        selectedVolume?.url.path == "/"
    }

    private var showsFullDiskAccessHint: Bool {
        // The banner exists only to prompt granting Full Disk Access, which only
        // matters for the boot volume. Once it's granted there's nothing left to
        // act on — any folders still unreadable are root-owned system paths that
        // FDA can't unlock — so we stop nagging instead of flagging them forever.
        !isScanning && selectedIsBootVolume && !fullDiskAccessGranted
    }

    private var fullDiskAccessHintText: String {
        "Grant Full Disk Access to DMonte Tool Box, then reopen this window and Rescan to measure every folder."
    }

    private var currentNode: DiskNode? {
        pathStack.last
    }

    private var selectedTreeCache: DiskTreeCache? {
        guard let id = selectedVolume?.id else { return nil }
        return treeCaches[id]
    }

    private func treemapRects(for node: DiskNode, size: CGSize) -> [TreemapRect] {
        guard size.width > 1, size.height > 1 else { return [] }
        let key = TreemapLayoutCacheKey(node: node, size: size)
        if let id = selectedVolume?.id, let cached = treemapLayoutCaches[id]?[key] {
            return cached
        }
        let bounds = CGRect(origin: .zero, size: size)
        return TreemapLayout.compute(nodes: node.children, in: bounds)
    }

    private func updateTreemapSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let rounded = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard treemapSize != rounded else { return }
        treemapSize = rounded

        if let selectedVolume, let root = treeCaches[selectedVolume.id]?.root {
            scheduleTreemapLayoutCache(for: selectedVolume.id, root: root)
        }
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

        // Drop cached results and tear down in-flight scans for volumes that
        // have gone away (e.g. an ejected external drive).
        let detectedIds = Set(detected.map(\.id))
        for goneId in treeCaches.keys where !detectedIds.contains(goneId) {
            treeCaches.removeValue(forKey: goneId)
            treemapLayoutCaches.removeValue(forKey: goneId)
            treemapLayoutTasks[goneId]?.cancel()
            treemapLayoutTasks.removeValue(forKey: goneId)
        }
        for goneId in Array(scanTasks.keys) where !detectedIds.contains(goneId) {
            scanGates[goneId]?.resume()
            scanTasks[goneId]?.cancel()
            scanTasks.removeValue(forKey: goneId)
            scanTrackers.removeValue(forKey: goneId)
            scanGates.removeValue(forKey: goneId)
            pausedVolumeIds.remove(goneId)
        }

        if let selectedVolume, !detected.contains(where: { $0.id == selectedVolume.id }) {
            self.selectedVolume = nil
            pathStack = []
            hoveredNode = nil
        }

        if autoSelectFirst, selectedVolume == nil, let first = detected.first {
            select(volume: first)
        }
    }

    private func select(volume: DiskVolume) {
        // Switching volumes must NOT cancel an in-flight scan — let it survive so
        // its result lands in the cache. Scan pause state is controlled only by
        // the pause button, so background scans keep running unless the user
        // explicitly pauses them.
        hoveredNode = nil
        selectedVolume = volume

        if let cached = treeCaches[volume.id] {
            pathStack = [cached.root]
            expandTreePath(to: cached.root)
            scheduleTreemapLayoutCache(for: volume.id, root: cached.root)
            return
        }

        pathStack = []
        if scanTasks[volume.id] == nil {
            startScan(volume: volume)
        }
    }

    private func rescan() {
        guard let selectedVolume else { return }
        let id = selectedVolume.id
        teardownScan(for: id)
        treeCaches.removeValue(forKey: id)
        treemapLayoutCaches.removeValue(forKey: id)
        treemapLayoutTasks[id]?.cancel()
        treemapLayoutTasks.removeValue(forKey: id)
        pathStack = []
        startScan(volume: selectedVolume)
    }

    private func startScan(volume: DiskVolume) {
        let volumeId = volume.id
        teardownScan(for: volumeId)
        hoveredNode = nil
        fullDiskAccessGranted = FullDiskAccess.isGranted()

        let generation = (scanGenerations[volumeId] ?? 0) + 1
        scanGenerations[volumeId] = generation

        let tracker = DiskScanProgressTracker()
        scanTrackers[volumeId] = tracker

        let gate = ScanPauseGate()
        scanGates[volumeId] = gate
        pausedVolumeIds.remove(volumeId)

        scanTasks[volumeId] = Task(priority: .userInitiated) {
            let node = await DiskScanner.scan(volume: volume, tracker: tracker, gate: gate)

            if Task.isCancelled {
                return
            }

            await MainActor.run {
                // Ignore a stale completion that a newer scan has superseded.
                guard scanGenerations[volumeId] == generation else { return }

                if let node {
                    let treeCache = DiskTreeCache(root: node)
                    treeCaches[volumeId] = treeCache
                    expandTreePath(to: node)
                    scheduleTreemapLayoutCache(for: volumeId, root: node)
                }
                if selectedVolume?.id == volumeId {
                    pathStack = node.map { [$0] } ?? []
                }
                scanTasks.removeValue(forKey: volumeId)
                scanTrackers.removeValue(forKey: volumeId)
                scanGates.removeValue(forKey: volumeId)
                pausedVolumeIds.remove(volumeId)
            }
        }
    }

    /// Tear down any in-flight scan for a volume (resume first so a paused task
    /// can observe cancellation), clearing all of its tracking state.
    private func teardownScan(for volumeId: String) {
        scanGates[volumeId]?.resume()
        scanTasks[volumeId]?.cancel()
        scanTasks.removeValue(forKey: volumeId)
        scanTrackers.removeValue(forKey: volumeId)
        scanGates.removeValue(forKey: volumeId)
        pausedVolumeIds.remove(volumeId)
    }

    private func scheduleTreemapLayoutCache(for volumeId: String, root: DiskNode) {
        guard treemapSize.width > 1, treemapSize.height > 1 else { return }
        let currentSize = treemapSize
        let rootKey = TreemapLayoutCacheKey(node: root, size: currentSize)
        if treemapLayoutCaches[volumeId]?[rootKey] != nil {
            return
        }

        treemapLayoutTasks[volumeId]?.cancel()
        treemapLayoutTasks[volumeId] = Task.detached(priority: .utility) {
            let cache = DiskTreemapLayoutCacheBuilder.build(root: root, size: currentSize)
            if Task.isCancelled { return }

            await MainActor.run {
                guard selectedVolume?.id == volumeId || treeCaches[volumeId]?.root.id == root.id else {
                    return
                }
                treemapLayoutCaches[volumeId] = cache
                treemapLayoutTasks.removeValue(forKey: volumeId)
            }
        }
    }

    private func toggleScanPause() {
        guard let id = selectedVolume?.id, let gate = scanGates[id] else { return }
        if pausedVolumeIds.contains(id) {
            gate.resume()
            pausedVolumeIds.remove(id)
        } else {
            gate.pause()
            pausedVolumeIds.insert(id)
        }
    }

    private func handleTap(node: DiskNode) {
        expandTreePath(to: node)
        scrollTree(to: node)

        guard node.isDirectory, !node.children.isEmpty else {
            hoveredNode = node
            return
        }

        if let path = selectedTreeCache?.path(to: node) {
            pathStack = path
        } else {
            pathStack.append(node)
        }
        hoveredNode = nil
    }

    private func navigateFromTree(node: DiskNode) {
        guard let cache = selectedTreeCache, let path = cache.path(to: node) else {
            return
        }

        expandTreePath(path)

        if node.isDirectory {
            pathStack = path
        } else {
            pathStack = Array(path.dropLast())
        }
        hoveredNode = node
    }

    private func toggleTreeExpansion(node: DiskNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }

        if expandedTreeNodeIDs.contains(node.id) {
            expandedTreeNodeIDs.remove(node.id)
        } else {
            expandedTreeNodeIDs.insert(node.id)
        }
    }

    private func expandTreePath(to node: DiskNode) {
        guard let path = selectedTreeCache?.path(to: node) else {
            if node.isDirectory {
                expandedTreeNodeIDs.insert(node.id)
            }
            return
        }
        expandTreePath(path)
    }

    private func expandTreePath(_ path: [DiskNode]) {
        for node in path where node.isDirectory && !node.children.isEmpty {
            expandedTreeNodeIDs.insert(node.id)
        }
    }

    private func scrollTree(to node: DiskNode) {
        treeScrollGeneration += 1
        treeScrollRequest = TreeScrollRequest(nodeID: node.id, generation: treeScrollGeneration)
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
        for task in scanTasks.values {
            task.cancel()
        }
        for task in treemapLayoutTasks.values {
            task.cancel()
        }
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

private struct DiskTreeRow: View {
    var node: DiskNode
    var depth: Int
    var expandedNodeIDs: Set<ObjectIdentifier>
    var currentNodeID: ObjectIdentifier?
    var highlightedNodeID: ObjectIdentifier?
    var layout: DiskAnalyzerLayout
    var onToggleExpand: (DiskNode) -> Void
    var onSelect: (DiskNode) -> Void
    var onReveal: (DiskNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Color.clear
                    .frame(width: CGFloat(depth) * layout.treeIndent)

                Button {
                    onToggleExpand(node)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.secondary.opacity(canExpand ? 0.001 : 0))

                        Image(systemName: disclosureIcon)
                            .font(.system(size: layout.treeDisclosureSize, weight: .bold))
                            .foregroundStyle(canExpand ? Color.secondary : Color.clear)
                    }
                    .frame(width: layout.treeDisclosureTapSize, height: layout.treeRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canExpand)
                .help(canExpand ? (isExpanded ? "Collapse" : "Expand") : "")
                .accessibilityLabel(isExpanded ? "Collapse \(node.name)" : "Expand \(node.name)")

                HStack(spacing: 6) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: layout.treeIconSize, weight: .semibold))
                        .foregroundStyle(node.isDirectory ? Color.accentColor.opacity(0.9) : .secondary)
                        .frame(width: layout.treeIconFrame, height: layout.treeRowHeight)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.system(size: layout.treeRowFontSize, weight: isCurrent ? .bold : .semibold))
                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.84))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(node.size.diskBytesString)
                            .font(.system(size: layout.treeRowSubFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: layout.treeRowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(node)
                }
                .contextMenu {
                    Button {
                        onReveal(node)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
            }
            .padding(.trailing, 8)
            .frame(height: layout.treeRowHeight)
            .background(rowBackground)

            if isExpanded {
                ForEach(node.children) { child in
                    DiskTreeRow(
                        node: child,
                        depth: depth + 1,
                        expandedNodeIDs: expandedNodeIDs,
                        currentNodeID: currentNodeID,
                        highlightedNodeID: highlightedNodeID,
                        layout: layout,
                        onToggleExpand: onToggleExpand,
                        onSelect: onSelect,
                        onReveal: onReveal
                    )
                }
            }
        }
        .id(node.id)
    }

    private var canExpand: Bool {
        node.isDirectory && !node.children.isEmpty
    }

    private var disclosureIcon: String {
        guard canExpand else { return "chevron.right" }
        return isExpanded ? "chevron.down" : "chevron.right"
    }

    private var isExpanded: Bool {
        expandedNodeIDs.contains(node.id)
    }

    private var isCurrent: Bool {
        currentNodeID == node.id
    }

    private var isHighlighted: Bool {
        highlightedNodeID == node.id
    }

    private var rowBackground: some ShapeStyle {
        if isCurrent {
            return Color.accentColor.opacity(0.20)
        }
        if isHighlighted {
            return Color.white.opacity(0.10)
        }
        return Color.clear
    }
}

private struct TreemapTile: View {
    var entry: TreemapRect
    var isHovered: Bool
    var layout: DiskAnalyzerLayout

    var body: some View {
        let color = DiskItemPalette.color(for: entry.node)
        let showName = entry.rect.width >= layout.tileNameMinWidth && entry.rect.height >= layout.tileNameMinHeight
        let showSize = showName && entry.rect.height >= layout.tileSizeMinHeight

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(isHovered ? 0.96 : 0.86))

            if showName {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.node.name)
                        .font(.system(size: layout.tileLabelFontSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)

                    if showSize {
                        Text(entry.node.size.diskBytesString)
                            .font(.system(size: layout.tileLabelFontSize - 1, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .clipped()
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
    var isPaused: Bool
    var onTogglePause: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let progress = tracker.snapshot
            let target = max(volume?.usedBytes ?? 0, 1)
            let estimatedRatio = Double(progress.bytesScanned) / Double(target)
            let exceededEstimate = estimatedRatio >= 1
            let folderFraction = directoryFraction(progress)
            let scanFraction = scanProgressFraction(byteRatio: estimatedRatio, folderFraction: folderFraction)
            let barFraction = scanBarFraction(scanFraction: scanFraction, exceededEstimate: exceededEstimate, folderFraction: folderFraction)

            VStack(alignment: .leading, spacing: layout.summarySpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(progress.bytesScanned.diskBytesString)
                        .font(.system(size: layout.summaryValueFontSize, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(progressSummary(progress))
                        .font(.system(size: layout.summarySubFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let volume {
                        Text(estimateLabel(scanFraction: scanFraction, exceededEstimate: exceededEstimate, volume: volume))
                            .font(.system(size: layout.summarySubFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
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
                                .frame(width: proxy.size.width * CGFloat(barFraction))
                                .opacity(isPaused ? 0.45 : 1)
                                .animation(.easeOut(duration: 0.18), value: barFraction)
                        }
                        .frame(height: layout.summaryBarHeight)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    }

                    Button(action: onTogglePause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: layout.summarySubFontSize, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: layout.summaryBarHeight + 16, height: layout.summaryBarHeight + 16)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isPaused ? "Resume scan" : "Pause scan")
                }

                HStack(spacing: 6) {
                    Image(systemName: isPaused ? "pause.circle.fill" : "magnifyingglass")
                        .font(.system(size: layout.summarySubFontSize - 1, weight: .semibold))
                        .foregroundStyle(isPaused ? Color.orange : .secondary)

                    Text(statusLabel(progress: progress, exceededEstimate: exceededEstimate, isPaused: isPaused))
                        .font(.system(size: layout.summarySubFontSize - 1, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func progressSummary(_ progress: DiskScanProgress) -> String {
        let discovered = max(progress.directoriesDiscovered, progress.directoriesScanned)
        return "\(progress.itemsScanned.formatted()) items · \(progress.directoriesScanned.formatted())/\(discovered.formatted()) folders"
    }

    private func directoryFraction(_ progress: DiskScanProgress) -> Double {
        let discovered = max(progress.directoriesDiscovered, progress.directoriesScanned, 1)
        return min(1, max(0, Double(progress.directoriesScanned) / Double(discovered)))
    }

    private func scanProgressFraction(byteRatio: Double, folderFraction: Double) -> Double {
        let boundedByteFraction = min(1, max(0, byteRatio))
        let boundedFolderFraction = min(1, max(0, folderFraction))

        if byteRatio >= 1 {
            return min(0.995, 0.96 + (0.035 * boundedFolderFraction))
        }

        return min(0.985, boundedByteFraction * (0.96 + (0.025 * boundedFolderFraction)))
    }

    private func scanBarFraction(scanFraction: Double, exceededEstimate: Bool, folderFraction: Double) -> Double {
        if exceededEstimate {
            return min(0.995, 0.96 + (0.035 * folderFraction))
        }
        return min(0.985, max(0.02, scanFraction))
    }

    private func estimateLabel(scanFraction: Double, exceededEstimate: Bool, volume: DiskVolume) -> String {
        let percent = min(99, max(0, Int((scanFraction * 100).rounded(.down))))
        if exceededEstimate {
            return "\(percent)% scanned"
        }
        return "\(percent)% of \(volume.usedBytes.diskBytesString) est."
    }

    private func statusLabel(progress: DiskScanProgress, exceededEstimate: Bool, isPaused: Bool) -> String {
        if isPaused {
            return "Paused — tap play to resume"
        }
        if exceededEstimate {
            let remaining = max(0, progress.directoriesDiscovered - progress.directoriesScanned)
            return "Scanning remaining folders · \(remaining.formatted()) known left"
        }
        return displayPath(progress.currentPath)
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
    var minWindowSize: NSSize { NSSize(width: 760, height: 460) }
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

    var analysisPaneSpacing: CGFloat { 12 * scale }
    var treemapCornerRadius: CGFloat { 10 * scale }
    var treemapInnerPadding: CGFloat { 10 * scale }
    var tileLabelFontSize: CGFloat { 11 * scale }
    var tileLabelMinSide: CGFloat { 56 * scale }
    // Lower thresholds so more (and smaller) tiles get at least a name label.
    var tileNameMinWidth: CGFloat { 36 * scale }
    var tileNameMinHeight: CGFloat { 18 * scale }
    var tileSizeMinHeight: CGFloat { 44 * scale }
    var hoverChipIconSize: CGFloat { 11 * scale }
    var hoverChipFontSize: CGFloat { 12 * scale }
    var emptyIconSize: CGFloat { 38 * scale }
    var emptyFontSize: CGFloat { 14 * scale }

    var treePaneWidth: CGFloat { 250 * scale }
    var treePaneCornerRadius: CGFloat { 10 * scale }
    var treePanePadding: CGFloat { 10 * scale }
    var treeHeaderVerticalPadding: CGFloat { 9 * scale }
    var treeHeaderIconSize: CGFloat { 13 * scale }
    var treeHeaderFontSize: CGFloat { 13 * scale }
    var treeMetaFontSize: CGFloat { 10.5 * scale }
    var treeRowHeight: CGFloat { 34 * scale }
    var treeIndent: CGFloat { 12 * scale }
    var treeDisclosureSize: CGFloat { 9 * scale }
    var treeDisclosureTapSize: CGFloat { 28 * scale }
    var treeIconSize: CGFloat { 12 * scale }
    var treeIconFrame: CGFloat { 16 * scale }
    var treeRowFontSize: CGFloat { 11.5 * scale }
    var treeRowSubFontSize: CGFloat { 9.5 * scale }
}
