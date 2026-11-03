import Foundation

/// The units a user sees. Storage and the API are always kilograms.
public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg
    case lb
}

/// A weight, held as exact kilograms (decided in llm.md: never round what's stored,
/// round only for display), so 157.5 lb round-trips as 157.5 lb.
public struct Weight: Equatable, Hashable, Codable, Sendable {
    /// Exact pounds per kilogram's inverse: 1 lb = 0.45359237 kg (international definition).
    public static let kilogramsPerPound = 0.45359237

    public let kilograms: Double

    public init(kilograms: Double) {
        self.kilograms = kilograms
    }

    public init(_ value: Double, _ unit: WeightUnit) {
        switch unit {
        case .kg: kilograms = value
        case .lb: kilograms = value * Self.kilogramsPerPound
        }
    }

    /// The exact value in `unit`, unrounded.
    public func value(in unit: WeightUnit) -> Double {
        switch unit {
        case .kg: kilograms
        case .lb: kilograms / Self.kilogramsPerPound
        }
    }

    /// The value in `unit`, rounded for display to the nearest `step` (default 0.1).
    public func displayValue(in unit: WeightUnit, step: Double = 0.1) -> Double {
        (value(in: unit) / step).rounded() * step
    }
}
