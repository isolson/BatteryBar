import Foundation
import SwiftUI

// MARK: - Charging Bottleneck

enum ChargingBottleneck {
    case limitedByCharger(adapterW: Int)
    case limitedByChargerOrCable(adapterW: Int, deliveringW: Int)
    case limitedByLaptop
    case slowingNearFull(soc: Int)
    case finishingCharge
    case chargingNormally(adapterW: Int?)
    case notCharging
    case detecting
    case none
}

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
    let temperature: Int?       // hundredths of a degree Celsius
    let avgTimeToFull: Int      // minutes, 65535 = N/A
    let avgTimeToEmpty: Int     // minutes, 65535 = N/A
    let designCapacity: Int?     // mAh
    let nominalChargeCapacity: Int? // mAh (current full capacity)

    // PowerTelemetryData
    let systemPowerIn: Int?     // mW; nil when input telemetry is unavailable
    let systemEnergyConsumed: Int // mW
    let batteryPower: Int64     // mW (signed)

    // Adapter info (from AppleRawAdapterDetails)
    let adapterWatts: Int?
    let adapterName: String?

    // Charging limits (from ChargerData)
    let chargingCurrent: Int
    let slowChargingReason: Int
    let notChargingReason: Int
    let thermallyLimited: Int       // cumulative seconds of thermal throttling

    // Efficiency (from PowerTelemetryData)
    let adapterEfficiencyLoss: Int  // mW

    // MARK: - Memberwise Init

    init(id: UUID, timestamp: Date, currentCapacity: Int, maxCapacity: Int, voltage: Int,
         amperage: Int, instantAmperage: Int, isCharging: Bool, externalConnected: Bool,
         cycleCount: Int, temperature: Int?, avgTimeToFull: Int, avgTimeToEmpty: Int,
         designCapacity: Int?, nominalChargeCapacity: Int?, systemPowerIn: Int?,
         systemEnergyConsumed: Int, batteryPower: Int64, adapterWatts: Int?,
         adapterName: String?, chargingCurrent: Int, slowChargingReason: Int,
         notChargingReason: Int, thermallyLimited: Int, adapterEfficiencyLoss: Int) {
        self.id = id; self.timestamp = timestamp; self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity; self.voltage = voltage; self.amperage = amperage
        self.instantAmperage = instantAmperage; self.isCharging = isCharging
        self.externalConnected = externalConnected; self.cycleCount = cycleCount
        self.temperature = temperature; self.avgTimeToFull = avgTimeToFull
        self.avgTimeToEmpty = avgTimeToEmpty; self.designCapacity = designCapacity
        self.nominalChargeCapacity = nominalChargeCapacity; self.systemPowerIn = systemPowerIn
        self.systemEnergyConsumed = systemEnergyConsumed; self.batteryPower = batteryPower
        self.adapterWatts = adapterWatts; self.adapterName = adapterName
        self.chargingCurrent = chargingCurrent; self.slowChargingReason = slowChargingReason
        self.notChargingReason = notChargingReason; self.thermallyLimited = thermallyLimited
        self.adapterEfficiencyLoss = adapterEfficiencyLoss
    }

    // MARK: - Backward-compatible Decoding

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        currentCapacity = try c.decode(Int.self, forKey: .currentCapacity)
        maxCapacity = try c.decode(Int.self, forKey: .maxCapacity)
        voltage = try c.decode(Int.self, forKey: .voltage)
        amperage = try c.decode(Int.self, forKey: .amperage)
        instantAmperage = try c.decode(Int.self, forKey: .instantAmperage)
        isCharging = try c.decode(Bool.self, forKey: .isCharging)
        externalConnected = try c.decode(Bool.self, forKey: .externalConnected)
        cycleCount = try c.decode(Int.self, forKey: .cycleCount)
        temperature = try c.decodeIfPresent(Int.self, forKey: .temperature)
        avgTimeToFull = try c.decode(Int.self, forKey: .avgTimeToFull)
        avgTimeToEmpty = try c.decode(Int.self, forKey: .avgTimeToEmpty)
        designCapacity = try c.decodeIfPresent(Int.self, forKey: .designCapacity)
        nominalChargeCapacity = try c.decodeIfPresent(Int.self, forKey: .nominalChargeCapacity)
        systemPowerIn = try c.decodeIfPresent(Int.self, forKey: .systemPowerIn)
        systemEnergyConsumed = try c.decode(Int.self, forKey: .systemEnergyConsumed)
        batteryPower = try c.decode(Int64.self, forKey: .batteryPower)
        // New fields — default to nil/0 for old data
        adapterWatts = try c.decodeIfPresent(Int.self, forKey: .adapterWatts)
        adapterName = try c.decodeIfPresent(String.self, forKey: .adapterName)
        chargingCurrent = try c.decodeIfPresent(Int.self, forKey: .chargingCurrent) ?? 0
        slowChargingReason = try c.decodeIfPresent(Int.self, forKey: .slowChargingReason) ?? 0
        notChargingReason = try c.decodeIfPresent(Int.self, forKey: .notChargingReason) ?? 0
        thermallyLimited = try c.decodeIfPresent(Int.self, forKey: .thermallyLimited) ?? 0
        adapterEfficiencyLoss = try c.decodeIfPresent(Int.self, forKey: .adapterEfficiencyLoss) ?? 0
    }

    // MARK: - Computed Properties

    var socPercent: Int { currentCapacity }

    var chargeWatts: Double {
        guard externalConnected, isCharging else { return 0 }
        // Prefer PowerTelemetryData, fall back to V*A
        if let systemPowerIn, systemPowerIn > 0 {
            return Double(systemPowerIn) / 1000.0
        }
        return abs(batteryChargeWatts)
    }

    var batteryChargeWatts: Double {
        // Power flowing into/out of battery: Voltage * Amperage
        return Double(voltage) * Double(amperage) / 1_000_000.0
    }

    var consumptionWatts: Double? {
        if externalConnected {
            // On AC: system consumption = adapter power - battery charge power
            guard let adapterW = deliveringWatts else { return nil }
            let batteryW = batteryChargeWatts // positive when charging
            return max(adapterW - batteryW, 0)
        } else {
            // On battery: consumption = |battery discharge|
            return abs(batteryChargeWatts)
        }
    }

    var temperatureCelsius: Double? {
        guard let temperature, temperature > 0 else { return nil }
        return Double(temperature) / 100.0
    }

    var voltageVolts: Double {
        Double(voltage) / 1000.0
    }

    var amperageAmps: Double {
        Double(amperage) / 1000.0
    }

    var timeRemainingMinutes: Int? {
        guard !isCharging || socPercent < 100 else { return nil }
        let minutes = isCharging ? avgTimeToFull : avgTimeToEmpty
        return (0..<65535).contains(minutes) ? minutes : nil
    }

    var batteryHealth: Double? {
        guard let designCapacity, designCapacity > 0,
              let nominalChargeCapacity, nominalChargeCapacity > 0 else { return nil }
        return Double(nominalChargeCapacity) / Double(designCapacity) * 100.0
    }

    var deliveringWatts: Double? {
        guard let systemPowerIn, systemPowerIn >= 0 else { return nil }
        return Double(systemPowerIn) / 1000.0
    }

    var chargingBottleneck: ChargingBottleneck {
        guard externalConnected else { return .none }

        // The percentage can reach 100 before macOS clears its charging flag.
        if socPercent >= 100 { return isCharging ? .finishingCharge : .none }

        // Connected but not charging at all
        if !isCharging && chargingCurrent == 0 {
            if let adapterW = adapterWatts, adapterW > 0, adapterW <= 30 {
                return .limitedByCharger(adapterW: adapterW)
            }
            return .notCharging
        }

        // Thermal throttling
        if slowChargingReason != 0 { return .limitedByLaptop }

        // Slowing near full
        if socPercent > 80 { return .slowingNearFull(soc: socPercent) }

        // Check charger utilization
        guard let delivering = deliveringWatts else { return .detecting }
        if let adapterW = adapterWatts, adapterW > 0 {
            if adapterW <= 30 {
                return .limitedByCharger(adapterW: adapterW)
            }
            // Ramp-up: delivering very little from a large adapter
            if delivering < 5 {
                return .detecting
            }
            if delivering >= Double(adapterW) * 0.9 {
                return .limitedByCharger(adapterW: adapterW)
            }
            if delivering < Double(adapterW) * 0.5 && delivering > 0 {
                return .limitedByChargerOrCable(adapterW: adapterW, deliveringW: Int(delivering))
            }
            return .chargingNormally(adapterW: adapterW)
        }

        return .chargingNormally(adapterW: nil)
    }
}
