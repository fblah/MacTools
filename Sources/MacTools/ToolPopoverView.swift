import SwiftUI

struct ToolPopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SystemMonitorHeader(onQuit: onQuit)

            LazyVGrid(columns: columns, spacing: 12) {
                LoadCard(snapshot: monitor.snapshot)
                MemoryCard(snapshot: monitor.snapshot)
                DiskCard(snapshot: monitor.snapshot)
                NetworkCard(snapshot: monitor.snapshot)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 540, height: 560)
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

private struct SystemMonitorHeader: View {
    var onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("System Monitor")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onQuit) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Quit MacTools")
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
}

private struct LoadCard: View {
    var snapshot: MetricSnapshot

    var body: some View {
        MonitorCard(badge: "waveform.path.ecg") {
            ArcGauge(value: snapshot.cpuUsage, color: .green, label: snapshot.cpuUsage.percentString)

            Spacer(minLength: 10)

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

            Spacer(minLength: 10)

            MetricTitle(icon: "memorychip", title: "MEMORY")
            Text("\(snapshot.memoryUsed.bytesString) of \(snapshot.memoryTotal.bytesString)")
                .font(.system(size: 21, weight: .semibold))
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
            VStack(spacing: 12) {
                Text(snapshot.diskUsage.percentString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                ProgressView(value: min(max(snapshot.diskUsage, 0), 1))
                    .tint(snapshot.diskUsage > 0.85 ? .yellow : .green)
                    .controlSize(.large)
                    .frame(width: 142)
            }

            Spacer(minLength: 12)

            MetricTitle(icon: "internaldrive", title: "Macintosh HD")
            Text("\(snapshot.diskUsed.bytesString) of \(snapshot.diskTotal.bytesString)")
                .font(.system(size: 21, weight: .semibold))
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
            VStack(alignment: .leading, spacing: 18) {
                NetworkRow(icon: "arrow.up", value: snapshot.networkUpRate.compactRateString)
                NetworkRow(icon: "arrow.down", value: snapshot.networkDownRate.compactRateString)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 28)

            Spacer(minLength: 12)

            MetricTitle(icon: "network", title: "Ethernet")
            Text("Network")
                .font(.system(size: 21, weight: .semibold))
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
        .padding(22)
        .frame(height: 214)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(10)
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .frame(width: 136, height: 106)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct MetricTitle: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 26)

            Text(title)
                .font(.system(size: 22, weight: .bold))
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
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26)

            Text(text)
                .font(.system(size: 21, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.secondary)
    }
}

private struct NetworkRow: View {
    var icon: String
    var value: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.18))
                .clipShape(Circle())

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }
}
