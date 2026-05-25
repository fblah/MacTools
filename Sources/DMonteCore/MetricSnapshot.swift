import Foundation

public struct MetricSnapshot: Equatable, Sendable {
    public var timestamp: Date
    public var cpuUsage: Double
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var diskUsed: UInt64
    public var diskTotal: UInt64
    public var networkDownRate: UInt64
    public var networkUpRate: UInt64
    public var batteryPercent: Double?
    public var isCharging: Bool
    public var uptime: TimeInterval
    public var cpuTemperatureCelsius: Double?

    public var memoryUsage: Double {
        guard memoryTotal > 0 else {
            return 0
        }

        return Double(memoryUsed) / Double(memoryTotal)
    }

    public var diskUsage: Double {
        guard diskTotal > 0 else {
            return 0
        }

        return Double(diskUsed) / Double(diskTotal)
    }

    public var diskAvailable: UInt64 {
        diskTotal > diskUsed ? diskTotal - diskUsed : 0
    }

    public init(
        timestamp: Date,
        cpuUsage: Double,
        memoryUsed: UInt64,
        memoryTotal: UInt64,
        diskUsed: UInt64,
        diskTotal: UInt64,
        networkDownRate: UInt64,
        networkUpRate: UInt64,
        batteryPercent: Double?,
        isCharging: Bool,
        uptime: TimeInterval,
        cpuTemperatureCelsius: Double?
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.networkDownRate = networkDownRate
        self.networkUpRate = networkUpRate
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.uptime = uptime
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
    }

    public static let placeholder = MetricSnapshot(
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
        uptime: 0,
        cpuTemperatureCelsius: nil
    )

    public static let preview = MetricSnapshot(
        timestamp: Date(),
        cpuUsage: 0.19,
        memoryUsed: 70 * 1_073_741_824,
        memoryTotal: 128 * 1_073_741_824,
        diskUsed: 812 * 1_073_741_824,
        diskTotal: 924 * 1_073_741_824,
        networkDownRate: 7 * 1_024,
        networkUpRate: 1 * 1_024,
        batteryPercent: nil,
        isCharging: false,
        uptime: 3 * 86_400 + 13 * 3_600,
        cpuTemperatureCelsius: 54.6
    )
}
