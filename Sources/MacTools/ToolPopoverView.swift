import AppKit
import SwiftUI

enum DefaultsKey {
    static let systemMonitorEnabled = "tool.systemMonitor.enabled"
}

struct ToolPopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    var popoverSize: NSSize
    var onCheckForUpdates: () -> Void
    var onQuit: () -> Void

    @AppStorage(DefaultsKey.systemMonitorEnabled) private var isSystemMonitorEnabled = true
    @State private var selectedSection = ToolboxSection.dashboard
    @State private var activeTool: ToolboxTool?
    @State private var searchText = ""
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ToolboxHeader(
                selectedSection: $selectedSection,
                searchText: $searchText,
                onSettings: { isShowingSettings = true }
            )

            Divider()

            if let activeTool {
                toolDetail(activeTool)
            } else {
                ToolboxDashboard(
                    selectedSection: selectedSection,
                    searchText: searchText,
                    snapshot: monitor.snapshot,
                    isSystemMonitorEnabled: $isSystemMonitorEnabled,
                    onOpenTool: { activeTool = $0 }
                )
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onCheckForUpdates: onCheckForUpdates, onQuit: onQuit)
        }
    }

    @ViewBuilder
    private func toolDetail(_ tool: ToolboxTool) -> some View {
        switch tool {
        case .systemMonitor:
            SystemMonitorDetail(
                snapshot: monitor.snapshot,
                onBack: { activeTool = nil },
                onSettings: { isShowingSettings = true }
            )
        }
    }
}

private enum ToolboxSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case library = "Library"
}

private enum ToolboxTool: String, CaseIterable, Identifiable {
    case systemMonitor = "System Monitor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .systemMonitor: "waveform.path.ecg.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .systemMonitor: .green
        }
    }
}

private struct ToolboxHeader: View {
    @Binding var selectedSection: ToolboxSection
    @Binding var searchText: String
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ToolboxSection.allCases, id: \.self) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 0) {
                        Text(section.rawValue)
                            .font(.system(size: 22, weight: section == selectedSection ? .semibold : .medium))
                            .foregroundStyle(section == selectedSection ? .primary : .secondary)
                            .frame(height: 58)

                        Rectangle()
                            .fill(section == selectedSection ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(width: 156)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .regular))
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(height: 62)
    }
}

private struct ToolboxDashboard: View {
    var selectedSection: ToolboxSection
    var searchText: String
    var snapshot: MetricSnapshot
    @Binding var isSystemMonitorEnabled: Bool
    var onOpenTool: (ToolboxTool) -> Void

    var body: some View {
        ScrollView {
            if selectedSection == .library {
                LibraryView(
                    searchText: searchText,
                    isSystemMonitorEnabled: $isSystemMonitorEnabled,
                    snapshot: snapshot,
                    onOpenTool: onOpenTool
                )
            } else {
                DashboardView(
                    searchText: searchText,
                    isSystemMonitorEnabled: isSystemMonitorEnabled,
                    snapshot: snapshot,
                    onOpenTool: onOpenTool
                )
            }
        }
    }
}

private struct DashboardView: View {
    var searchText: String
    var isSystemMonitorEnabled: Bool
    var snapshot: MetricSnapshot
    var onOpenTool: (ToolboxTool) -> Void

    private var visibleTools: [ToolboxTool] {
        guard isSystemMonitorEnabled else {
            return []
        }

        return filtered([.systemMonitor])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("D'Monte's Toolbox")
                .font(.system(size: 28, weight: .bold))

            if visibleTools.isEmpty {
                EmptyToolsView()
            } else {
                ToolGrid(tools: visibleTools, snapshot: snapshot, onOpenTool: onOpenTool)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 28)
        .frame(minHeight: 556, alignment: .topLeading)
    }

    private func filtered(_ tools: [ToolboxTool]) -> [ToolboxTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return tools
        }

        return tools.filter { $0.rawValue.localizedCaseInsensitiveContains(query) }
    }
}

private struct LibraryView: View {
    var searchText: String
    @Binding var isSystemMonitorEnabled: Bool
    var snapshot: MetricSnapshot
    var onOpenTool: (ToolboxTool) -> Void

    private var tools: [ToolboxTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return ToolboxTool.allCases
        }

        return ToolboxTool.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Library")
                .font(.system(size: 28, weight: .bold))

            ForEach(tools) { tool in
                LibraryToolRow(
                    tool: tool,
                    snapshot: snapshot,
                    isEnabled: binding(for: tool),
                    onOpenTool: onOpenTool
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 28)
        .frame(minHeight: 556, alignment: .topLeading)
    }

    private func binding(for tool: ToolboxTool) -> Binding<Bool> {
        switch tool {
        case .systemMonitor:
            $isSystemMonitorEnabled
        }
    }
}

private struct ToolGrid: View {
    var tools: [ToolboxTool]
    var snapshot: MetricSnapshot
    var onOpenTool: (ToolboxTool) -> Void

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
            ForEach(tools) { tool in
                ToolboxIcon(tool: tool, snapshot: snapshot) {
                    onOpenTool(tool)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(124), spacing: 28), count: 5)
    }
}

private struct ToolboxIcon: View {
    var tool: ToolboxTool
    var snapshot: MetricSnapshot
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tool.tint.opacity(0.13))
                        .frame(width: 88, height: 88)

                    Image(systemName: tool.icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(tool.tint)

                    Text(snapshot.cpuUsage.percentString)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(Capsule())
                        .offset(x: 30, y: 30)
                }

                Text(tool.rawValue)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 124, height: 44, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryToolRow: View {
    var tool: ToolboxTool
    var snapshot: MetricSnapshot
    @Binding var isEnabled: Bool
    var onOpenTool: (ToolboxTool) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: tool.icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tool.tint)
                .frame(width: 46, height: 46)
                .background(tool.tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.rawValue)
                    .font(.system(size: 17, weight: .semibold))

                Text("CPU \(snapshot.cpuUsage.percentString)  RAM \(snapshot.memoryUsage.percentString)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onOpenTool(tool)
            } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
            .help("Open")

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyToolsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "switch.2")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No tools enabled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct SystemMonitorDetail: View {
    var snapshot: MetricSnapshot
    var onBack: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help("Back")

                Text("System Monitor")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            LazyVGrid(columns: columns, spacing: 12) {
                LoadCard(snapshot: snapshot)
                MemoryCard(snapshot: snapshot)
                DiskCard(snapshot: snapshot)
                NetworkCard(snapshot: snapshot)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)

            Spacer(minLength: 0)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.92),
                    Color(nsColor: .controlBackgroundColor).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }
}

private struct LoadCard: View {
    var snapshot: MetricSnapshot

    var body: some View {
        MonitorCard(badge: "waveform.path.ecg") {
            ArcGauge(value: snapshot.cpuUsage, color: .green, label: snapshot.cpuUsage.percentString)

            Spacer(minLength: 8)

            MetricTitle(icon: "cpu", title: "CPU LOAD")
            SecondaryLine(icon: "clock", text: "Uptime \(snapshot.uptime.compactDurationString)")
        }
    }
}

private struct MemoryCard: View {
    var snapshot: MetricSnapshot

    var body: some View {
        MonitorCard(badge: "memorychip") {
            ArcGauge(value: snapshot.memoryUsage, color: .green, label: snapshot.memoryUsage.percentString)

            Spacer(minLength: 8)

            MetricTitle(icon: "memorychip", title: "MEMORY")
            Text("\(snapshot.memoryUsed.bytesString) of \(snapshot.memoryTotal.bytesString)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct DiskCard: View {
    var snapshot: MetricSnapshot

    var body: some View {
        MonitorCard(badge: "paintbrush.pointed") {
            VStack(spacing: 10) {
                Text(snapshot.diskUsage.percentString)
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                ProgressView(value: min(max(snapshot.diskUsage, 0), 1))
                    .tint(snapshot.diskUsage > 0.85 ? .yellow : .green)
                    .controlSize(.large)
                    .frame(width: 132)
            }

            Spacer(minLength: 10)

            MetricTitle(icon: "internaldrive", title: "Macintosh HD")
            Text("\(snapshot.diskUsed.bytesString) of \(snapshot.diskTotal.bytesString)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct NetworkCard: View {
    var snapshot: MetricSnapshot

    var body: some View {
        MonitorCard(badge: "arrow.up.arrow.down") {
            NetworkStack(
                downRate: snapshot.networkDownRate.compactRateString,
                upRate: snapshot.networkUpRate.compactRateString
            )
            .padding(.top, 14)

            Spacer(minLength: 10)

            MetricTitle(icon: "network", title: "Ethernet")
            Text("Network")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MonitorCard<Content: View>: View {
    var badge: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(height: 178)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.72),
                            Color(nsColor: .controlBackgroundColor).opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: badge)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(9)
        }
    }
}

private struct ArcGauge: View {
    var value: Double
    var color: Color
    var label: String

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(90))

            Text(label)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
        .frame(width: 120, height: 88)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct MetricTitle: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary)
    }
}

private struct SecondaryLine: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)

            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.secondary)
    }
}

private struct NetworkStack: View {
    var downRate: String
    var upRate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NetworkLine(icon: "arrow.down", value: downRate)
            NetworkLine(icon: "arrow.up", value: upRate)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NetworkLine: View {
    var icon: String
    var value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.18))
                .clipShape(Circle())

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(width: 150, alignment: .leading)
    }
}

private struct SettingsView: View {
    var onCheckForUpdates: () -> Void
    var onQuit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("D'Monte's Toolbox Settings")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Button(action: onCheckForUpdates) {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(role: .destructive, action: onQuit) {
                Label("Quit D'Monte's Toolbox", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 360, height: 220)
    }
}
