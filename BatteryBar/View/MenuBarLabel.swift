import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let reading: BatteryReading?

    var body: some View {
        if let r = reading {
            Image(nsImage: renderLabel(r))
        } else {
            Text("--")
        }
    }

    private func renderLabel(_ r: BatteryReading) -> NSImage {
        let str = NSMutableAttributedString()

        let numFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let unitFont = NSFont.systemFont(ofSize: 6, weight: .regular)
        let arrowFont = NSFont.systemFont(ofSize: 11, weight: .regular)

        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .baselineOffset: 0
        ]
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .baselineOffset: 1
        ]
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: arrowFont,
            .baselineOffset: 0
        ]

        if r.externalConnected {
            let num = BatteryFormatters.formatWattsNumber(r.chargeWatts)
            str.append(NSAttributedString(string: num, attributes: numAttrs))
            str.append(NSAttributedString(string: "w", attributes: unitAttrs))
            str.append(NSAttributedString(string: "\u{2191} ", attributes: arrowAttrs))
        }

        let consNum = BatteryFormatters.formatWattsNumber(r.consumptionWatts)
        str.append(NSAttributedString(string: consNum, attributes: numAttrs))
        str.append(NSAttributedString(string: "w", attributes: unitAttrs))
        str.append(NSAttributedString(string: "\u{2193} ", attributes: arrowAttrs))

        str.append(NSAttributedString(string: "\(r.socPercent)", attributes: numAttrs))
        str.append(NSAttributedString(string: "%", attributes: unitAttrs))

        // Render at 2x for Retina
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = str.size()
        let logicalSize = NSSize(width: ceil(size.width), height: 18)
        let pixelSize = NSSize(width: logicalSize.width * scale, height: logicalSize.height * scale)

        let image = NSImage(size: logicalSize)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = logicalSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        str.draw(at: NSPoint(x: 0, y: 1))
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
