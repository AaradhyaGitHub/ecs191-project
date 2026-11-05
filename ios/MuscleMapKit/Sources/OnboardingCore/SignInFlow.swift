import Foundation
import Models
import Networking
import Observation

/// Phone number → code → signed in (AC-6, AC-7).
@MainActor
@Observable
public final class SignInFlow {
    public enum State: Equatable, Sendable {
        case enterPhone
        case enterCode
        case signedIn(User)
    }

    /// How long after a send "Resend code" stays off (Q-5).
    public static let resendCooldown: TimeInterval = 30

    /// What the user typed on the phone screen (digits after the fixed "+1").
    public var phoneText = ""
    /// What the user typed on the code screen.
    public var codeText = ""
    public private(set) var state: State = .enterPhone
    /// The message to show under the field, or nil.
    public private(set) var errorText: String?
    /// True while a call is running.
    public private(set) var isBusy = false

    @ObservationIgnored private let api: any OnboardingAPI
    @ObservationIgnored private let now: () -> Date

    public init(api: any OnboardingAPI, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    /// Checks the number, texts a code, and moves to `.enterCode`.
    public func sendCode() async {
        // scaffold
    }

    /// Sends a new code, once the cooldown has passed.
    public func resend() async {
        // scaffold
    }

    /// Checks the code; on success loads the profile and ends `.signedIn`.
    public func verify() async {
        // scaffold
    }

    /// Back to the phone screen, keeping the digits typed.
    public func changeNumber() {
        // scaffold
    }

    /// Whole seconds until "Resend code" is allowed, by the injected clock; 0 when allowed.
    public func resendAvailableIn() -> Int {
        0  // scaffold
    }
}
