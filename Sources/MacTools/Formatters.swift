import Foundation

extension Double {
    var percentString: String {
        let value = (self * 100).rounded()
        return "\(Int(value))%"
    }
}

extension UInt64 {
    var bytesString: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary)
    }

    var rateString: String {
        "\(bytesString)/s"
    }

    var compactBytesString: String {
        bytesString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".0", with: "")
    }

    var compactRateString: String {
        "\(compactBytesString)/s"
    }
}

extension TimeInterval {
    var compactDurationString: String {
        let totalMinutes = Int(self / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}
