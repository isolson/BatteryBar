import Foundation

struct BatteryReading: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Raw IOKit values
    let currentCapacity: Int
    let maxCapacity: Int
    let voltage: Int            // mV
    let amperage: Int           // mA (signed, negative = discharging)
    let instantAmperage: Int    // mA
    let isCharging: Bool
    let externalConnected: Bool
    let cycleCount: Int
    let temperature: Int        // deci-Kelvin
    let avgTimeToFull: Int      // minutes, 65535 = N/A
    let avgTimeToEmpty: Int     // minutes, 65535 = N/A
    let designCapacity: Int     // mAh
    let nominalChargeCapacity: Int // mAh (current full capacity)

    // PowerTelemetryData
    let systemPowerIn: Int      // mW
    let systemEnergyConsumed: Int // mW
    let batteryPower: Int64     // mW (signed)

    // MARK: - Computed Properties

    var socPercent: Int { currentCapacity }

    var chargeWatts: Double {
        guard externalConnected else { return 0 }
        // Battery full and not actively charging
        if socPercent >= 100 && !isCharging { return 0 }
        // Prefer PowerTelemetryData, fall back to V*A
        if systemPowerIn > 0 {
            return Double(systemPowerIn) / 1000.0
        }
        if isCharging {
            return abs(batteryChargeWatts)
        }
        return 0
    }

    var batteryChargeWatts: Double {
        // Power flowing into/out of battery: Voltage * Amperage
        return Double(voltage) * Double(amperage) / 1_000_000.0
    }

    var consumptionWatts: Double {
        if externalConnected {
            // On AC: system consumption = adapter power - battery charge power
            let adapterW = Double(systemPowerIn) / 1000.0
            let batteryW = batteryChargeWatts // positive when charging
            return max(adapterW - batteryW, 0)
        } else {
            // On battery: consumption = |battery discharge|
            return abs(batteryChargeWatts)
        }
    }

    var temperatureCelsius: Double {
        Double(temperature) / 10.0 - 273.15
    }

    var voltageVolts: Double {
        Double(voltage) / 1000.0
    }

    var amperageAmps: Double {
        Double(amperage) / 1000.0
    }

    var timeRemainingMinutes: Int? {
        if isCharging {
            return avgTimeToFull == 65535 ? nil : avgTimeToFull
        } else {
            return avgTimeToEmpty == 65535 ? nil : avgTimeToEmpty
        }
    }

    var batteryHealth: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(nominalChargeCapacity) / Double(designCapacity) * 100.0
    }
}
