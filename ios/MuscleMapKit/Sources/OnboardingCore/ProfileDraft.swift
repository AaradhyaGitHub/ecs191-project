import Foundation
import Models

/// The profile setup form (AC-8). Body weight is typed in `units` and sent as exact kg.
public struct ProfileDraft: Equatable, Sendable {
    public var displayName: String
    public private(set) var units: WeightUnit
    /// The body weight as typed, in `units`.
    public var bodyweightText: String
    /// "female", "male", or nil for "Prefer not to say" (Q-7).
    public var sex: String?
    public var birthYear: Int?
    public var experience: Experience?

    /// Prefilled from the saved profile.
    public init(user: User) {
        // scaffold
        displayName = ""
        units = .kg
        bodyweightText = ""
        sex = nil
        birthYear = nil
        experience = nil
    }

    /// Switches units, converting the typed body weight.
    public mutating func setUnits(_ unit: WeightUnit) {
        // scaffold
    }

    /// Why the form can't be saved, or nil.
    public var validationError: String? {
        nil  // scaffold
    }

    /// The `PUT /users/me` body for this form.
    public func update() -> UserUpdate {
        UserUpdate()  // scaffold
    }
}
