import Foundation

struct MetricSnapshot: Equatable {
    var timestamp: Date
    var cpuUsage: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskUsed: UInt64
    var diskTotal: UInt64
    var networkDownRate: UInt64
    var networkUpRate: UInt64
    var batteryPercent: Double?
    var isCharging: Bool
    var uptime: TimeInterval

    var memoryUsage: Double {
        guard memoryTotal > 0 else {
            return 0
        }

        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskUsage: Double {
        guard diskTotal > 0 else {
            return 0
        }

        return Double(diskUsed) / Double(diskTotal)
    }

    var diskAvailable: UInt64 {
        diskTotal > diskUsed ? diskTotal - diskUsed : 0
    }

    static let placeholder = MetricSnapshot(
        timestamp: Date(),
        cpuUsage: 0,
        memoryUsed: 0,
        memoryTotal: 0,
        diskUsed: 0,
        diskTotal: 0,
        networkDownRate: 0,
        networkUpRate: 0,
        batteryPercent: nil,
        isCharging: false,
        uptime: 0
    )
}
