import SwiftUI

/// The web app's loading wave (Ondu comes from "onde"): a wave with a fainter one behind
/// it moving the other way. Same formulas as `Loading.tsx` on the web, in a 60 by 20 box
/// with the line in the middle; keep the two in step.
struct LoadingWave: View {
    var width: CGFloat = 90

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let boxWidth = 60.0
    private static let middle = 10.0

    var body: some View {
        TimelineView(.animation) { context in
            // Reduced motion slows the wave down rather than replacing it.
            let t = context.date.timeIntervalSince(start) * (reduceMotion ? 0.25 : 1)
            Canvas { graphics, size in
                graphics.scaleBy(x: size.width / Self.boxWidth, y: size.width / Self.boxWidth)
                let back = Self.path { x in
                    3 * Self.drift(t, period: 2.9, amount: 0.5) * Self.envelope(x, t)
                        * Self.wave(x, -t, wavelength: 14, period: 1.2)
                }
                let front = Self.path { x in
                    4.5 * Self.drift(t, period: 3.7, amount: 0.3) * Self.envelope(x, t)
                        * Self.wave(x, t, wavelength: 10, period: 0.8)
                }
                graphics.stroke(
                    back, with: .color(.accentColor.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                graphics.stroke(
                    front, with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: width, height: width / 3)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.25),
                    .init(color: .black, location: 0.75),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .accessibilityLabel("Loading")
    }

    // A sine wave moving to the left, for x at time t (seconds)
    private static func wave(_ x: Double, _ t: Double, wavelength: Double, period: Double) -> Double {
        sin(2 * .pi * (x / wavelength + t / period))
    }

    // Slowly moves between 1 - amount and 1, so the height varies over time
    private static func drift(_ t: Double, period: Double, amount: Double) -> Double {
        1 - amount / 2 + (amount / 2) * sin(2 * .pi * t / period)
    }

    // Flat at both ends and tallest around the middle, where the tallest point
    // slowly sways from side to side.
    private static func envelope(_ x: Double, _ t: Double) -> Double {
        let center = boxWidth / 2 + 6 * sin(2 * .pi * t / 4.3)
        let flatEnds = pow(sin(.pi * x / boxWidth), 2)
        return flatEnds * exp(-pow((x - center) / 18, 2))
    }

    private static func path(_ y: (Double) -> Double) -> Path {
        var path = Path()
        for x in stride(from: 0.0, through: boxWidth, by: 1) {
            let point = CGPoint(x: x, y: middle + y(x))
            if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
