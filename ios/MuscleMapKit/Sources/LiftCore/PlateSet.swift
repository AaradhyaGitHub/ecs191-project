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
public struct PlateLoad: Equatable, Sendable {
    public let plateSet: PlateSet
    /// One entry per pair, in the order added.
    public private(set) var pairs: [Double]

    public init(plateSet: PlateSet, pairs: [Double] = []) {
        self.plateSet = plateSet
        self.pairs = pairs
    }

    /// Adds a pair of `plate` (one per side), unless the bar would go over 1000 kg (D-25).
    public mutating func add(_ plate: Double) {
        guard canAdd(plate) else { return }
        pairs.append(plate)
    }

    /// Whether a pair of `plate` keeps the bar at or under 1000 kg.
    public func canAdd(_ plate: Double) -> Bool {
        Weight(total + 2 * plate, plateSet.unit).kilograms <= WorkoutLimits.weightKg.upperBound
    }

    /// Removes the last pair added (tapping the bar). The empty bar stays.
    public mutating func removeLast() {
        _ = pairs.popLast()
    }

    /// Back to the empty bar.
    public mutating func reset() {
        pairs.removeAll()
    }

    /// The plates on one side, in `plateSet.unit`.
    public var perSide: Double { pairs.reduce(0, +) }

    /// Bar plus both sides, in `plateSet.unit`.
    public var total: Double { plateSet.bar + 2 * perSide }

    /// "45 bar + 55 per side".
    public var breakdown: String {
        "\(numberText(plateSet.bar)) bar + \(numberText(perSide)) per side"
    }

    /// The heaviest load the plates can make that is not above `target` (in `plateSet.unit`);
    /// 157 lb gives 155 lb. Below the bar, the empty bar.
    public static func nearestLoad(to target: Double, with plateSet: PlateSet) -> PlateLoad {
        var load = PlateLoad(plateSet: plateSet)
        var left = (target - plateSet.bar) / 2
        // Every plate is a multiple of the smallest one, so heaviest-first reaches the best load.
        for plate in plateSet.plates.sorted(by: >) {
            while left >= plate - 1e-9 {
                load.add(plate)
                left -= plate
            }
        }
        return load
    }
}
