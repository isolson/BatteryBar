import Foundation

/// Build-time text length validation.
/// Run via `make test` to ensure no UI string exceeds its display budget.
enum TextLengthTests {
    static func runAll() {
        testBottleneckTexts()
        testFormatWatts()
        testFormatTimeRemaining()
        testTimeWithSuffix()
        print("All text length tests passed.")
    }

    // Verdict line bottleneck text: must fit alongside time text in 250pt panel
    // At .caption (~10pt), ~28 chars is the safe max for the left side
    private static func testBottleneckTexts() {
        let maxLen = 28
        let cases: [ChargingBottleneck] = [
            .limitedByCharger(adapterW: 140),
            .limitedByChargerOrCable(adapterW: 140, deliveringW: 60),
            .limitedByLaptop,
            .slowingNearFull(soc: 95),
            .chargingNormally(adapterW: 140),
            .chargingNormally(adapterW: nil),
            .notCharging,
            .detecting,
            .none,
        ]
        for bottleneck in cases {
            let text = BatteryFormatters.bottleneckText(bottleneck)
            assert(text.count <= maxLen,
                "bottleneckText too long (\(text.count)/\(maxLen)): \"\(text)\"")
        }
    }

    // formatWatts: "XXXW" or "X.XW" — max 5 chars
    private static func testFormatWatts() {
        let maxLen = 5
        let values: [Double] = [0, 0.5, 5.5, 9.9, 10, 58, 100, 140]
        for w in values {
            let text = BatteryFormatters.formatWatts(w)
            assert(text.count <= maxLen,
                "formatWatts too long (\(text.count)/\(maxLen)): \"\(text)\" for \(w)W")
        }
    }

    // formatTimeRemaining: "XXm" or "X.Xh" — max 5 chars
    private static func testFormatTimeRemaining() {
        let maxLen = 5
        let values: [Int?] = [nil, 0, 1, 30, 59, 60, 90, 120, 600, 960]
        for m in values {
            let text = BatteryFormatters.formatTimeRemaining(m)
            assert(text.count <= maxLen,
                "formatTimeRemaining too long (\(text.count)/\(maxLen)): \"\(text)\" for \(String(describing: m))m")
        }
    }

    // Time + suffix: "Xh to full" or "Xm left" — max 13 chars
    private static func testTimeWithSuffix() {
        let maxLen = 13
        let values: [Int] = [1, 30, 59, 60, 90, 120, 600, 960]
        for m in values {
            let base = BatteryFormatters.formatTimeRemaining(m)
            let full = base + " to full"
            let left = base + " left"
            assert(full.count <= maxLen,
                "time+toFull too long (\(full.count)/\(maxLen)): \"\(full)\"")
            assert(left.count <= maxLen,
                "time+left too long (\(left.count)/\(maxLen)): \"\(left)\"")
        }
    }
}
