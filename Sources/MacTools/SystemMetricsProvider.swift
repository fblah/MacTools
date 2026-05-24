import Foundation
import IOKit.ps
import MachO
import Darwin

final class SystemMetricsProvider {
    private var previousCPU: (idle: UInt64, total: UInt64)?
    private var previousNetwork: (timestamp: Date, down: UInt64, up: UInt64)?

    func sample() -> MetricSnapshot {
        let timestamp = Date()
        let memory = memoryUsage()
        let disk = diskUsage()
        let network = networkRates(at: timestamp)
        let battery = batteryStatus()

        return MetricSnapshot(
            timestamp: timestamp,
            cpuUsage: cpuUsage(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownRate: network.downRate,
            networkUpRate: network.upRate,
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func cpuUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return 0
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        var idle: UInt64 = 0
        var total: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)

        for cpuIndex in 0..<Int(processorCount) {
            let offset = cpuIndex * stride
            let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            let cpuIdle = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])

            idle += cpuIdle
            total += user + system + nice + cpuIdle
        }

        defer {
            previousCPU = (idle: idle, total: total)
        }

        guard let previousCPU else {
            return 0
        }

        let totalDelta = total.subtractingReportingOverflow(previousCPU.total)
        let idleDelta = idle.subtractingReportingOverflow(previousCPU.idle)

        guard !totalDelta.overflow, !idleDelta.overflow, totalDelta.partialValue > 0 else {
            return 0
        }

        let busy = totalDelta.partialValue - idleDelta.partialValue
        return min(max(Double(busy) / Double(totalDelta.partialValue), 0), 1)
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory

        guard result == KERN_SUCCESS else {
            return (used: 0, total: total)
        }

        let pageSize = UInt64(getpagesize())
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return (used: active + wired + compressed, total: total)
    }

    private func diskUsage() -> (used: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            return (used: total > available ? total - available : 0, total: total)
        } catch {
            return (used: 0, total: 0)
        }
    }

    private func networkRates(at timestamp: Date) -> (downRate: UInt64, upRate: UInt64) {
        let totals = networkTotals()

        defer {
            previousNetwork = (timestamp: timestamp, down: totals.down, up: totals.up)
        }

        guard let previousNetwork else {
            return (downRate: 0, upRate: 0)
        }

        let elapsed = max(timestamp.timeIntervalSince(previousNetwork.timestamp), 0.1)
        let downDelta = totals.down >= previousNetwork.down ? totals.down - previousNetwork.down : 0
        let upDelta = totals.up >= previousNetwork.up ? totals.up - previousNetwork.up : 0

        return (
            downRate: UInt64(Double(downDelta) / elapsed),
            upRate: UInt64(Double(upDelta) / elapsed)
        )
    }

    private func networkTotals() -> (down: UInt64, up: UInt64) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        var down: UInt64 = 0
        var up: UInt64 = 0

        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return (down: down, up: up)
        }

        defer {
            freeifaddrs(addresses)
        }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee

            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }

            let name = String(cString: interface.ifa_name)

            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") else {
                continue
            }

            down += UInt64(data.ifi_ibytes)
            up += UInt64(data.ifi_obytes)
        }

        return (down: down, up: up)
    }

    private func batteryStatus() -> (percent: Double?, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (percent: nil, isCharging: false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let max = description[kIOPSMaxCapacityKey] as? Double,
                  max > 0 else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            return (
                percent: current / max,
                isCharging: state == kIOPSACPowerValue
            )
        }

        return (percent: nil, isCharging: false)
    }
}
