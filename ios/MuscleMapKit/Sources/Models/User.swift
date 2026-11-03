import Foundation

public enum Experience: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate, advanced
}

/// The signed-in user's profile (`GET /users/me`).
public struct User: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var sex: String?
    public var birthYear: Int?
    public var bodyweightKg: Double?
    /// Display only; storage is always kg.
    public var units: WeightUnit
    public var experience: Experience?
    public var createdAt: Date
}

/// A partial profile update (`PUT /users/me`): only the fields that are set are sent.
public struct UserUpdate: Codable, Hashable, Sendable {
    public var displayName: String?
    public var sex: String?
    public var birthYear: Int?
    public var bodyweightKg: Double?
    public var units: WeightUnit?
    public var experience: Experience?

    public init(displayName: String? = nil, sex: String? = nil, birthYear: Int? = nil,
                bodyweightKg: Double? = nil, units: WeightUnit? = nil,
                experience: Experience? = nil) {
        self.displayName = displayName
        self.sex = sex
        self.birthYear = birthYear
        self.bodyweightKg = bodyweightKg
        self.units = units
        self.experience = experience
    }
}

/// `GET /health`.
public struct Health: Codable, Hashable, Sendable {
    public var status: String
}
