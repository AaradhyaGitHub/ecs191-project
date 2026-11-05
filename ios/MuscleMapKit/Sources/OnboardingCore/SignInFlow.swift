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

    static let invalidNumberText = "Enter a 10-digit US phone number."
    static let invalidCodeText = "Enter the 6-digit code."

    /// What the user typed on the phone screen (digits after the fixed "+1").
    public var phoneText = ""
    /// What the user typed on the code screen.
    public var codeText = ""
    public private(set) var state: State = .enterPhone
    /// The message to show under the field, or nil.
    public private(set) var errorText: String?
    /// True while a call is running.
    public private(set) var isBusy = false
    /// The number the code was sent to, E.164 ("+15305550000"); nil before the first send.
    public private(set) var sentTo: String?

    @ObservationIgnored private let api: any OnboardingAPI
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastSentAt: Date?
    /// True once the code was accepted (the token is saved). A spent code can't be checked
    /// again, so a later Verify only retries loading the profile.
    @ObservationIgnored private var isVerified = false

    public init(api: any OnboardingAPI, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    /// Checks the number, texts a code, and moves to `.enterCode`.
    public func sendCode() async {
        guard !isBusy else { return }
        guard let number = PhoneNumber.e164(from: phoneText) else {
            errorText = Self.invalidNumberText
            return
        }
        if await send(to: number) {
            codeText = ""
            state = .enterCode
        }
    }

    /// Sends a new code, once the cooldown has passed.
    public func resend() async {
        guard !isBusy, state == .enterCode, let sentTo, resendAvailableIn() == 0 else { return }
        _ = await send(to: sentTo)
    }

    /// Checks the code; on success loads the profile and ends `.signedIn`.
    /// If the profile can't load, it stays on the code screen (the token is kept) so the user
    /// can try again; that next Verify only loads the profile, since the code is spent.
    public func verify() async {
        guard !isBusy, state == .enterCode, let sentTo else { return }
        guard isVerified || VerificationCode.isValid(codeText) else {
            errorText = Self.invalidCodeText
            return
        }
        isBusy = true
        defer { isBusy = false }
        if !isVerified {
            do {
                _ = try await api.verifySignIn(phoneNumber: sentTo, code: codeText)
                isVerified = true
            } catch {
                errorText = OnboardingErrors.isUnauthorized(error)
                    ? OnboardingErrors.wrongCode : OnboardingErrors.text(for: error)
                return
            }
        }
        do {
            let user = try await api.me()
            errorText = nil
            state = .signedIn(user)
        } catch {
            errorText = OnboardingErrors.text(for: error)
        }
    }

    /// Back to the phone screen, keeping the digits typed.
    public func changeNumber() {
        guard !isBusy else { return }
        codeText = ""
        errorText = nil
        isVerified = false
        state = .enterPhone
    }

    /// Whole seconds until "Resend code" is allowed, by the injected clock; 0 when allowed.
    public func resendAvailableIn() -> Int {
        guard let lastSentAt else { return 0 }
        let left = lastSentAt.addingTimeInterval(Self.resendCooldown).timeIntervalSince(now())
        return max(0, Int(left.rounded(.up)))
    }

    /// Calls `POST /auth/sms/start`; true on success.
    private func send(to number: String) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.startSignIn(phoneNumber: number)
            sentTo = number
            lastSentAt = now()
            errorText = nil
            return true
        } catch {
            errorText = OnboardingErrors.text(for: error)
            return false
        }
    }
}
