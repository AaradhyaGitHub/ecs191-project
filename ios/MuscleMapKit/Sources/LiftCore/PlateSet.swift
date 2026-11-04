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

/// The plates on the bar in the plate loader (plan: specs/log-workout.llm.md, "Plates").
/// Each plate is a pair, one per side. Values are in `plateSet.unit`.
/// SCAFFOLD: the methods return valid but wrong values. Build mode fills them in.
public struct PlateLoad: Equatable, Sendable {
    public let plateSet: PlateSet
    /// One entry per pair, in the order added.
    public private(set) var pairs: [Double]

    public init(plateSet: PlateSet, pairs: [Double] = []) {
        self.plateSet = plateSet
        self.pairs = pairs
    }

    /// Adds a pair of `plate` (one per side).
    public mutating func add(_ plate: Double) {
    }

    /// Removes the last pair added (tapping the bar). The empty bar stays.
    public mutating func removeLast() {
    }

    /// Back to the empty bar.
    public mutating func reset() {
    }

    /// Bar plus both sides, in `plateSet.unit`.
    public var total: Double { 0 }

    /// "45 bar + 55 per side".
    public var breakdown: String { "" }

    /// The heaviest load the plates can make that is not above `target` (in `plateSet.unit`);
    /// 157 lb gives 155 lb. Below the bar, the empty bar.
    public static func nearestLoad(to target: Double, with plateSet: PlateSet) -> PlateLoad {
        PlateLoad(plateSet: plateSet)
    }
}
