import Foundation

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

    static func formatWattsNumber(_ watts: Double) -> String {
        if watts >= 10 {
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
}
