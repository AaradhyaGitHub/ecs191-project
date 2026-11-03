import Models

/// A bar and the plates the plate loader offers (decided in llm.md: both lb and kg).
public struct PlateSet: Equatable, Sendable {
    public let unit: WeightUnit
    public let bar: Double
    /// Plate sizes in `unit`, heaviest first. The loader adds them in pairs.
    public let plates: [Double]

    public init(unit: WeightUnit, bar: Double, plates: [Double]) {
        self.unit = unit
        self.bar = bar
        self.plates = plates
    }

    public static let pounds = PlateSet(unit: .lb, bar: 45, plates: [45, 35, 25, 10, 5, 2.5])
    public static let kilograms = PlateSet(unit: .kg, bar: 20, plates: [25, 20, 15, 10, 5, 2.5, 1.25])

    public static func standard(for unit: WeightUnit) -> PlateSet {
        unit == .lb ? .pounds : .kilograms
    }
}
