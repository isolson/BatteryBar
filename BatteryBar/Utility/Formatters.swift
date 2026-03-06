import Foundation
import SwiftUI

enum BatteryFormatters {
    static func formatTemperature(_ celsius: Double) -> String {
        String(format: "%.1f°C", celsius)
    }

    static func formatTimeRemaining(_ minutes: Int?) -> String {
        guard let minutes = minutes else { return "--" }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = Double(minutes) / 60.0
        return String(format: "%.1fh", hours)
    }

    static func formatWattsNumber(_ watts: Double, rounded: Bool = false) -> String {
        if rounded || watts >= 10 {
            return String(format: "%.0f", watts)
        } else {
            return String(format: "%.1f", watts)
        }
    }

    static func formatWatts(_ watts: Double) -> String {
        return formatWattsNumber(watts) + "W"
    }

    static func formatVoltage(_ volts: Double) -> String {
        String(format: "%.2fV", volts)
    }

    static func formatAmperage(_ amps: Double) -> String {
        String(format: "%.2fA", amps)
    }

    static func formatHealth(_ health: Double) -> String {
        String(format: "%.0f%%", health)
    }

    static func bottleneckText(_ bottleneck: ChargingBottleneck) -> String {
        switch bottleneck {
        case .limitedByCharger:
            return "Slower charge"
        case .limitedByChargerOrCable:
            return "Slow charge \u{2014} check cable"
        case .limitedByLaptop:
            return "Paused \u{2014} too warm"
        case .slowingNearFull:
            return "Slowing near full"
        case .chargingNormally:
            return "Charging at full speed"
        case .notCharging:
            return "On AC \u{2014} not charging"
        case .detecting:
            return "Detecting\u{2026}"
        case .none:
            return ""
        }
    }

    static func bottleneckColor(_ bottleneck: ChargingBottleneck) -> Color {
        switch bottleneck {
        case .limitedByCharger, .limitedByChargerOrCable:
            return .yellow
        case .limitedByLaptop:
            return .orange
        case .slowingNearFull, .notCharging, .detecting:
            return .gray
        case .chargingNormally:
            return .green
        case .none:
            return .clear
        }
    }
}
