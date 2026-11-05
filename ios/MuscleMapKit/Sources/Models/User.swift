import Foundation

public enum Experience: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate, advanced
}

/// The signed-in user's profile (`GET /users/me`).
public struct User: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// `nil` for a new user who hasn't set a name.
    public var displayName: String?
    public var sex: String?
    public var birthYear: Int?
    public var bodyweightKg: Double?
    /// Display only; storage is always kg.
    public var units: WeightUnit
    public var experience: Experience?
    /// Whether the user finished onboarding (API.md; `false` for a new user).
    public var onboardingCompleted: Bool
    public var createdAt: Date

    public init(id: String, displayName: String? = nil, sex: String? = nil, birthYear: Int? = nil,
                bodyweightKg: Double? = nil, units: WeightUnit, experience: Experience? = nil,
                onboardingCompleted: Bool = false, createdAt: Date) {
        self.id = id
        self.displayName = displayName
        self.sex = sex
        self.birthYear = birthYear
        self.bodyweightKg = bodyweightKg
        self.units = units
        self.experience = experience
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
    }
}

/// A partial profile update (`PUT /users/me`): only the fields that are set are sent.
public struct UserUpdate: Codable, Hashable, Sendable {
    public var displayName: String?
    public var sex: String?
    public var birthYear: Int?
    public var bodyweightKg: Double?
    public var units: WeightUnit?
    public var experience: Experience?
    public var onboardingCompleted: Bool?

    public init(displayName: String? = nil, sex: String? = nil, birthYear: Int? = nil,
                bodyweightKg: Double? = nil, units: WeightUnit? = nil,
                experience: Experience? = nil, onboardingCompleted: Bool? = nil) {
        self.displayName = displayName
        self.sex = sex
        self.birthYear = birthYear
        self.bodyweightKg = bodyweightKg
        self.units = units
        self.experience = experience
        self.onboardingCompleted = onboardingCompleted
    }
}

/// `GET /health`.
public struct Health: Codable, Hashable, Sendable {
    public var status: String
}

/// The result of `POST /auth/sms/verify`: the token to send as `Authorization: Bearer`.
public struct SignIn: Codable, Hashable, Sendable {
    public var token: String
    public var userId: String

    public init(token: String, userId: String) {
        self.token = token
        self.userId = userId
    }
}
