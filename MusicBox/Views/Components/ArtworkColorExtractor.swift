import SwiftUI
import Nuke

nonisolated enum ArtworkColorExtractor {
    static func extractColor(from url: URL?, maxBrightness: CGFloat = 0.7) async -> Color? {
        guard let url else { return nil }
        let request = ImageRequest(url: url, processors: [.resize(width: 50)])
        let image: PlatformImage?
        if let cached = ImagePipeline.shared.cache[request] {
            image = cached.image
        } else {
            image = try? await ImagePipeline.shared.image(for: request)
        }
        guard let image else { return nil }
        guard let cgColor = dominantColor(from: image, maxBrightness: maxBrightness) else { return nil }
        return Color(cgColor)
    }

    static func dominantColor(from image: PlatformImage, maxBrightness: CGFloat = 0.7) -> CGColor? {
        #if os(iOS)
        guard let cgImage = image.cgImage else { return nil }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif
        let size = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &data, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Collect HSB for each pixel, weighting by saturation so colorful pixels dominate
        var weightedH: Double = 0
        var weightedS: Double = 0
        var weightedB: Double = 0
        var totalWeight: Double = 0

        let count = size * size
        for i in 0..<count {
            let offset = i * 4
            let r = CGFloat(data[offset]) / 255.0
            let g = CGFloat(data[offset + 1]) / 255.0
            let b = CGFloat(data[offset + 2]) / 255.0

            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
            #if os(iOS)
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
            #else
            NSColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
            #endif

            // Skip very dark or very bright pixels — they add gray/white
            guard br > 0.15 && br < 0.95 else { continue }

            // Weight by saturation squared so colorful pixels win
            let weight = Double(s * s + 0.05)
            // Use sin/cos for hue to handle wraparound (red = 0/1)
            weightedH += sin(Double(h) * 2 * .pi) * weight
            weightedS += Double(s) * weight
            weightedB += Double(br) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            // All pixels were too dark/bright — fall back to simple average
            return fallbackAverageColor(data: data, count: count, maxBrightness: maxBrightness)
        }

        let avgAngle = atan2(weightedH / totalWeight, cos(asin(weightedH / totalWeight)))
        // Reconstruct hue from weighted sin average
        var sinSum: Double = 0, cosSum: Double = 0
        for i in 0..<count {
            let offset = i * 4
            let r = CGFloat(data[offset]) / 255.0
            let g = CGFloat(data[offset + 1]) / 255.0
            let b = CGFloat(data[offset + 2]) / 255.0
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
            #if os(iOS)
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
            #else
            NSColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
            #endif
            guard br > 0.15 && br < 0.95 else { continue }
            let weight = Double(s * s + 0.05)
            sinSum += sin(Double(h) * 2 * .pi) * weight
            cosSum += cos(Double(h) * 2 * .pi) * weight
        }

        var avgH = atan2(sinSum / totalWeight, cosSum / totalWeight) / (2 * .pi)
        if avgH < 0 { avgH += 1 }
        let avgS = weightedS / totalWeight
        let avgB = weightedB / totalWeight

        let finalS = min(avgS * 1.5, 1.0)
        let finalB = min(max(avgB, 0.3), maxBrightness)

        #if os(iOS)
        return UIColor(hue: avgH, saturation: finalS, brightness: finalB, alpha: 1).cgColor
        #else
        return NSColor(hue: avgH, saturation: finalS, brightness: finalB, alpha: 1).cgColor
        #endif
    }

    private static func fallbackAverageColor(data: [UInt8], count: Int, maxBrightness: CGFloat) -> CGColor? {
        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0
        for i in 0..<count {
            let offset = i * 4
            totalR += Double(data[offset])
            totalG += Double(data[offset + 1])
            totalB += Double(data[offset + 2])
        }
        let r = totalR / Double(count) / 255.0
        let g = totalG / Double(count) / 255.0
        let b = totalB / Double(count) / 255.0

        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
        #if os(iOS)
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
        return UIColor(hue: h, saturation: min(s * 1.5, 1.0), brightness: min(max(br, 0.3), maxBrightness), alpha: 1).cgColor
        #else
        NSColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
        return NSColor(hue: h, saturation: min(s * 1.5, 1.0), brightness: min(max(br, 0.3), maxBrightness), alpha: 1).cgColor
        #endif
    }
}
