import Foundation
import Networking

/// Texts and checks shared by the onboarding flows (Q-7).
enum OnboardingErrors {
    static let offline = "Can't reach the server."
    static let wrongCode = "That code isn't right."
    static let generic = "Something went wrong. Try again."

    /// True for a 401, with or without API.md's error body.
    static func isUnauthorized(_ error: Error) -> Bool {
        switch error as? APIError {
        case .server(status: 401, _, _), .unexpectedStatus(401): true
        default: false
        }
    }

    /// What to show for a failed call. A 400 or 403 shows the server's own message.
    static func text(for error: Error) -> String {
        switch error as? APIError {
        case .transport: offline
        case let .server(status, _, message) where status == 400 || status == 403: message
        default: generic
        }
    }
}
