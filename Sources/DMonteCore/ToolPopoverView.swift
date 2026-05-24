import AppKit
import SwiftUI

public enum DefaultsKey {
    public static let systemMonitorEnabled = "tool.systemMonitor.enabled"
}

@MainActor
public enum AppDefaults {
    public static let shared = UserDefaults(suiteName: "com.havokentity.mactools.shared") ?? .standard

    public static func registerDefaults() {
        shared.register(defaults: [
            DefaultsKey.systemMonitorEnabled: true
        ])
    }
}

public struct ToolPopoverView: View {
    var popoverSize: NSSize
    var onOpenSystemMonitor: () -> Void
    var onCheckForUpdates: () -> Void
    var onQuit: () -> Void

    @AppStorage(DefaultsKey.systemMonitorEnabled, store: AppDefaults.shared) private var isSystemMonitorEnabled = true
    @State private var selectedSection = ToolboxSection.dashboard
    @State private var searchText = ""
    @State private var isShowingSettings = false

    public init(
        popoverSize: NSSize,
        onOpenSystemMonitor: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.popoverSize = popoverSize
        self.onOpenSystemMonitor = onOpenSystemMonitor
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolboxHeader(
                    selectedSection: $selectedSection,
                    searchText: $searchText,
                    onSettings: { isShowingSettings = true },
                    onQuit: onQuit
                )

                Divider()

                ToolboxDashboard(
                    selectedSection: selectedSection,
                    searchText: searchText,
                    isSystemMonitorEnabled: $isSystemMonitorEnabled,
                    onOpenTool: onOpenSystemMonitor
                )
            }

            if isShowingSettings {
                PreferencesOverlay(cornerRadius: 18) {
                    SettingsView(
                        onCheckForUpdates: onCheckForUpdates,
                        onQuit: onQuit,
                        onClose: { isShowingSettings = false }
                    )
                }
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .frostedPanel(cornerRadius: 18)
    }

}

private extension View {
    func frostedPanel(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.64, green: 0.61, blue: 0.78).opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.75)
        }
    }
}

private struct PreferencesOverlay<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.38))

            content
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.68))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    var onQuit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ToolboxSection.allCases, id: \.self) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 0) {
                        Text(section.rawValue)
                            .font(.system(size: 15, weight: section == selectedSection ? .semibold : .medium))
                            .foregroundStyle(section == selectedSection ? .primary : .secondary)
                            .frame(height: 40)

                        Rectangle()
                            .fill(section == selectedSection ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(width: 96)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(height: 44)
    }
}

private struct ToolboxDashboard: View {
    var selectedSection: ToolboxSection
    var searchText: String
    @Binding var isSystemMonitorEnabled: Bool
    var onOpenTool: () -> Void

    var body: some View {
        ScrollView {
            if selectedSection == .library {
                LibraryView(
                    searchText: searchText,
                    isSystemMonitorEnabled: $isSystemMonitorEnabled,
                    onOpenTool: onOpenTool
                )
            } else {
                DashboardView(
                    searchText: searchText,
                    isSystemMonitorEnabled: isSystemMonitorEnabled,
                    onOpenTool: onOpenTool
                )
            }
        }
    }
}

private struct DashboardView: View {
    var searchText: String
    var isSystemMonitorEnabled: Bool
    var onOpenTool: () -> Void

    private var visibleTools: [ToolboxTool] {
        guard isSystemMonitorEnabled else {
            return []
        }

        return filtered([.systemMonitor])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("D'Monte's Toolbox")
                .font(.system(size: 18, weight: .bold))

            Text("Enable tools in Library. Each enabled tool gets its own menu bar item.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if visibleTools.isEmpty {
                EmptyToolsView()
            } else {
                ToolGrid(tools: visibleTools, onOpenTool: onOpenTool)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(minHeight: 330, alignment: .topLeading)
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
    var onOpenTool: () -> Void

    private var tools: [ToolboxTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return ToolboxTool.allCases
        }

        return ToolboxTool.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Library")
                .font(.system(size: 18, weight: .bold))

            ForEach(tools) { tool in
                LibraryToolRow(
                    tool: tool,
                    isEnabled: binding(for: tool),
                    onOpenTool: onOpenTool
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(minHeight: 330, alignment: .topLeading)
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
    var onOpenTool: () -> Void

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(tools) { tool in
                ToolboxIcon(tool: tool) {
                    onOpenTool()
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 76, maximum: 84), spacing: 14)]
    }
}

private struct ToolboxIcon: View {
    var tool: ToolboxTool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tool.tint.opacity(0.13))
                        .frame(width: 54, height: 54)

                    Image(systemName: tool.icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(tool.tint)
                }

                Text(tool.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 82, height: 30, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryToolRow: View {
    var tool: ToolboxTool
    @Binding var isEnabled: Bool
    var onOpenTool: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(tool.tint)
                .frame(width: 34, height: 34)
                .background(tool.tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.rawValue)
                    .font(.system(size: 15, weight: .semibold))

                Text("Separate menu bar tool")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onOpenTool()
            } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
            .help("Open")

            GreenSwitch(isOn: $isEnabled)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GreenSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? Color.green : Color.secondary.opacity(0.30))
                .frame(width: 42, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enabled")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct EmptyToolsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "switch.2")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No tools enabled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

public struct SystemMonitorPopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    var onQuit: () -> Void
    @State private var isShowingSettings = false
    private let layout = SystemMonitorPanelLayout.current

    public init(monitor: SystemMonitor, onQuit: @escaping () -> Void) {
        self.monitor = monitor
        self.onQuit = onQuit
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("System Monitor")
                        .font(.system(size: layout.titleFontSize, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: layout.settingsIconSize, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: layout.settingsButtonSize, height: layout.settingsButtonSize)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding(.horizontal, layout.headerHorizontalPadding)
                .padding(.vertical, layout.headerVerticalPadding)

                LazyVGrid(columns: columns, spacing: layout.gridSpacing) {
                    LoadCard(snapshot: monitor.snapshot, layout: layout)
                    MemoryCard(snapshot: monitor.snapshot, layout: layout)
                    DiskCard(snapshot: monitor.snapshot, layout: layout)
                    NetworkCard(snapshot: monitor.snapshot, layout: layout)
                }
                .padding(.horizontal, layout.gridHorizontalPadding)
                .padding(.bottom, layout.gridBottomPadding)

                Spacer(minLength: 0)
            }

            if isShowingSettings {
                PreferencesOverlay(cornerRadius: 18) {
                    SystemMonitorSettingsView(
                        onQuit: onQuit,
                        onClose: { isShowingSettings = false }
                    )
                }
            }
        }
        .frostedPanel(cornerRadius: 18)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: layout.gridSpacing),
            GridItem(.flexible(), spacing: layout.gridSpacing)
        ]
    }
}

private struct SystemMonitorPanelLayout {
    let scale: CGFloat

    static var current: SystemMonitorPanelLayout {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = min(1.0, max(0.88, visibleFrame.height / 950))
        return SystemMonitorPanelLayout(scale: scale)
    }

    var titleFontSize: CGFloat { 15 * scale }
    var settingsIconSize: CGFloat { 15 * scale }
    var settingsButtonSize: CGFloat { 26 * scale }
    var headerHorizontalPadding: CGFloat { 16 * scale }
    var headerVerticalPadding: CGFloat { 9 * scale }
    var gridHorizontalPadding: CGFloat { 10 * scale }
    var gridBottomPadding: CGFloat { 8 * scale }
    var gridSpacing: CGFloat { 8 * scale }
    var cardHeight: CGFloat { 130 * scale }
    var cardPadding: CGFloat { 8 * scale }
    var cardCornerRadius: CGFloat { 14 * scale }
    var badgeSize: CGFloat { 20 * scale }
    var badgeFontSize: CGFloat { 10.5 * scale }
    var badgePadding: CGFloat { 6 * scale }
    var badgeCornerRadius: CGFloat { 7 * scale }
    var visualGap: CGFloat { 7 * scale }
    var gaugeWidth: CGFloat { 72 * scale }
    var gaugeHeight: CGFloat { 48 * scale }
    var gaugeLineWidth: CGFloat { 7 * scale }
    var gaugeFontSize: CGFloat { 18 * scale }
    var diskPercentFontSize: CGFloat { 20 * scale }
    var diskProgressWidth: CGFloat { 98 * scale }
    var metricIconSize: CGFloat { 12 * scale }
    var metricIconWidth: CGFloat { 16 * scale }
    var metricFontSize: CGFloat { 12 * scale }
    var secondaryIconSize: CGFloat { 11 * scale }
    var secondaryFontSize: CGFloat { 11 * scale }
    var detailFontSize: CGFloat { 12.5 * scale }
    var networkSpacing: CGFloat { 6 * scale }
    var networkIconSize: CGFloat { 18 * scale }
    var networkIconFontSize: CGFloat { 10 * scale }
    var networkValueFontSize: CGFloat { 15 * scale }
    var networkLineWidth: CGFloat { 100 * scale }
}

private struct LoadCard: View {
    var snapshot: MetricSnapshot
    var layout: SystemMonitorPanelLayout

    var body: some View {
        MonitorCard(badge: "waveform.path.ecg", layout: layout) {
            ArcGauge(value: snapshot.cpuUsage, color: .green, label: snapshot.cpuUsage.percentString, layout: layout)

            Color.clear.frame(height: layout.visualGap)

            MetricTitle(icon: "cpu", title: "CPU LOAD", layout: layout)
            SecondaryLine(icon: "clock", text: "Uptime \(snapshot.uptime.compactDurationString)", layout: layout)
        }
    }
}

private struct MemoryCard: View {
    var snapshot: MetricSnapshot
    var layout: SystemMonitorPanelLayout

    var body: some View {
        MonitorCard(badge: "memorychip", layout: layout) {
            ArcGauge(value: snapshot.memoryUsage, color: .green, label: snapshot.memoryUsage.percentString, layout: layout)

            Color.clear.frame(height: layout.visualGap)

            MetricTitle(icon: "memorychip", title: "MEMORY", layout: layout)
            Text("\(snapshot.memoryUsed.bytesString) of \(snapshot.memoryTotal.bytesString)")
                .font(.system(size: layout.detailFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct DiskCard: View {
    var snapshot: MetricSnapshot
    var layout: SystemMonitorPanelLayout

    var body: some View {
        MonitorCard(badge: "paintbrush.pointed", layout: layout) {
            VStack(alignment: .center, spacing: 6) {
                Text(snapshot.diskUsage.percentString)
                    .font(.system(size: layout.diskPercentFontSize, weight: .bold, design: .rounded))

                ProgressView(value: min(max(snapshot.diskUsage, 0), 1))
                    .tint(snapshot.diskUsage > 0.85 ? .yellow : .green)
                    .controlSize(.large)
                    .frame(width: layout.diskProgressWidth)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Color.clear.frame(height: layout.visualGap)

            MetricTitle(icon: "internaldrive", title: "Macintosh HD", layout: layout)
            Text("\(snapshot.diskUsed.bytesString) of \(snapshot.diskTotal.bytesString)")
                .font(.system(size: layout.detailFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct NetworkCard: View {
    var snapshot: MetricSnapshot
    var layout: SystemMonitorPanelLayout

    var body: some View {
        MonitorCard(badge: "arrow.up.arrow.down", layout: layout) {
            NetworkStack(
                downRate: snapshot.networkDownRate.compactRateString,
                upRate: snapshot.networkUpRate.compactRateString,
                layout: layout
            )

            Color.clear.frame(height: layout.visualGap)

            MetricTitle(icon: "network", title: "Ethernet", layout: layout)
            Text("Network")
                .font(.system(size: layout.detailFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct MonitorCard<Content: View>: View {
    var badge: String
    var layout: SystemMonitorPanelLayout
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            content
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity)
        .frame(height: layout.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
        .overlay {
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: badge)
                .font(.system(size: layout.badgeFontSize, weight: .semibold))
                .foregroundStyle(.green.opacity(0.55))
                .frame(width: layout.badgeSize, height: layout.badgeSize)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: layout.badgeCornerRadius, style: .continuous))
                .padding(layout.badgePadding)
        }
    }
}

private struct ArcGauge: View {
    var value: Double
    var color: Color
    var label: String
    var layout: SystemMonitorPanelLayout

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: layout.gaugeLineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: layout.gaugeLineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))

            Text(label)
                .font(.system(size: layout.gaugeFontSize, weight: .bold, design: .rounded))
        }
        .frame(width: layout.gaugeWidth, height: layout.gaugeHeight)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct MetricTitle: View {
    var icon: String
    var title: String
    var layout: SystemMonitorPanelLayout

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: layout.metricIconSize, weight: .bold))
                .frame(width: layout.metricIconWidth)

            Text(title)
                .font(.system(size: layout.metricFontSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SecondaryLine: View {
    var icon: String
    var text: String
    var layout: SystemMonitorPanelLayout

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: layout.secondaryIconSize, weight: .semibold))
                .frame(width: layout.metricIconWidth)

            Text(text)
                .font(.system(size: layout.secondaryFontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NetworkStack: View {
    var downRate: String
    var upRate: String
    var layout: SystemMonitorPanelLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.networkSpacing) {
            NetworkLine(icon: "arrow.down", value: downRate, layout: layout)
            NetworkLine(icon: "arrow.up", value: upRate, layout: layout)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NetworkLine: View {
    var icon: String
    var value: String
    var layout: SystemMonitorPanelLayout

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: layout.networkIconFontSize, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
                .frame(width: layout.networkIconSize, height: layout.networkIconSize)
                .background(Color.secondary.opacity(0.18))
                .clipShape(Circle())

            Text(value)
                .font(.system(size: layout.networkValueFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(width: layout.networkLineWidth, alignment: .center)
    }
}

private struct SettingsView: View {
    var onCheckForUpdates: () -> Void
    var onQuit: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("D'Monte's Toolbox Settings")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Button {
                    onClose()
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

            Button {
                onQuit()
            } label: {
                Label("Quit D'Monte's Toolbox", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()
        }
        .padding(22)
        .frame(width: 360, height: 220)
    }
}

private struct SystemMonitorSettingsView: View {
    var onQuit: () -> Void
    var onClose: () -> Void

    @AppStorage(DefaultsKey.systemMonitorEnabled, store: AppDefaults.shared) private var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("System Monitor Settings")
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

            HStack(spacing: 14) {
                Text("Show System Monitor in menu bar")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                GreenSwitch(isOn: $isEnabled)
            }

            Divider()

            Text("This tool owns its tray item, monitor popup, and settings. Disable it here or from the Toolbox Library.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                onClose()
                onQuit()
            } label: {
                Label("Quit System Monitor", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 320, height: 230)
    }
}
