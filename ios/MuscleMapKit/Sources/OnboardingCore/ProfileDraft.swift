import Foundation
import Models

/// The profile setup form (AC-8). Body weight is typed in `units` and sent as exact kg.
public struct ProfileDraft: Equatable, Sendable {
    /// Same limit as `WorkoutLimits.maxBodyweightKg` (copied so this module needn't import LiftCore).
    public static let maxBodyweightKg = 500.0
    /// Q-11: the client checks the name length; the server's limits are #51.
    public static let maxNameLength = 60
    public static let earliestBirthYear = 1900

    public var displayName: String
    public private(set) var units: WeightUnit
    /// The body weight as typed, in `units`.
    public var bodyweightText: String
    /// "female", "male", or nil for "Prefer not to say" (Q-7).
    public var sex: String?
    public var birthYear: Int?
    public var experience: Experience?

    /// The saved kg and the text it was shown as, so an untouched weight is sent back exactly.
    private var savedBodyweight: (kg: Double, text: String)?

    /// Prefilled from the saved profile.
    public init(user: User) {
        displayName = user.displayName ?? ""
        units = user.units
        sex = user.sex
        birthYear = user.birthYear
        experience = user.experience
        if let kg = user.bodyweightKg {
            let text = Self.format(Weight(kilograms: kg).displayValue(in: user.units))
            bodyweightText = text
            savedBodyweight = (kg, text)
        } else {
            bodyweightText = ""
        }
    }

    public static func == (lhs: ProfileDraft, rhs: ProfileDraft) -> Bool {
        lhs.displayName == rhs.displayName && lhs.units == rhs.units
            && lhs.bodyweightText == rhs.bodyweightText && lhs.sex == rhs.sex
            && lhs.birthYear == rhs.birthYear && lhs.experience == rhs.experience
    }

    /// Switches units, converting the typed body weight.
    public mutating func setUnits(_ unit: WeightUnit) {
        guard unit != units else { return }
        let kg = bodyweightKg
        units = unit
        if let kg {
            bodyweightText = Self.format(Weight(kilograms: kg).displayValue(in: unit))
            if savedBodyweight != nil { savedBodyweight = (kg, bodyweightText) }
        }
    }

    /// Why the form can't be saved, or nil.
    public var validationError: String? {
        if trimmedName.count > Self.maxNameLength {
            return "Name can be at most \(Self.maxNameLength) characters."
        }
        if !trimmedWeightText.isEmpty {
            guard let kg = bodyweightKg, kg.isFinite, kg > 0, kg <= Self.maxBodyweightKg else {
                let max = Self.format(Weight(kilograms: Self.maxBodyweightKg).value(in: units).rounded(.down))
                return "Body weight must be above 0 and at most \(max) \(units.rawValue)."
            }
        }
        if let birthYear, !(Self.earliestBirthYear...Self.currentYear).contains(birthYear) {
            return "Birth year must be between \(Self.earliestBirthYear) and \(Self.currentYear)."
        }
        return nil
    }

    /// The `PUT /users/me` body for this form.
    public func update() -> UserUpdate {
        UserUpdate(displayName: trimmedName.isEmpty ? nil : trimmedName,
                   sex: sex, birthYear: birthYear, bodyweightKg: bodyweightKg,
                   units: units, experience: experience)
    }

    // MARK: Helpers

    public static var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedWeightText: String { bodyweightText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The typed weight in exact kg; nil when blank or not a number.
    private var bodyweightKg: Double? {
        if let savedBodyweight, savedBodyweight.text == bodyweightText { return savedBodyweight.kg }
        let text = trimmedWeightText.replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let value = Double(text) else { return nil }
        return Weight(value, units).kilograms
    }

    /// 220.5 → "220.5", 80.0 → "80".
    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
