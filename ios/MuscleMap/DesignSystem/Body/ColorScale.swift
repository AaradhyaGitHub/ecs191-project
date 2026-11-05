import SwiftUI
import BodyCore

/// Maps a 0–1 value to a color by blending between color stops,
/// like a CSS `linear-gradient` you sample at one point.
struct ColorScale {
    struct Stop {
        var position: Double
        var color: RGB
    }

    /// Plain red/green/blue numbers. SwiftUI's `Color` can't be blended directly,
    /// so stops are stored like this and converted at the end.
    struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(red: red + (other.red - red) * t,
                green: green + (other.green - green) * t,
                blue: blue + (other.blue - blue) * t)
        }

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// Must be sorted by position, covering 0...1.
    var stops: [Stop]

    init(_ stops: [(Double, UInt32)]) {
        self.stops = stops.map { Stop(position: $0.0, color: RGB(hex: $0.1)) }
    }

    func rgb(at value: Double) -> RGB {
        guard let first = stops.first, let last = stops.last else { return RGB(hex: 0xFFFFFF) }
        let v = min(max(value, 0), 1)
        if v <= first.position { return first.color }
        for (a, b) in zip(stops, stops.dropFirst()) where v <= b.position {
            let t = (v - a.position) / max(b.position - a.position, .ulpOfOne)
            return a.color.mixed(with: b.color, t)
        }
        return last.color
    }

    func color(at value: Double) -> Color {
        rgb(at: value).color
    }
}
