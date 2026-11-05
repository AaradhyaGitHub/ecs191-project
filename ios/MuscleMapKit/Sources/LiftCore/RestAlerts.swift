import Foundation

// Rest countdown beeps and notices (specs/lift-feedback.llm.md, AC-1 to AC-3).
// The app plays the cues while it is open and schedules the notices for when it is closed
// or locked (Decided 1 and 2). A timer counts as ended once `now >= endsAt`.

/// The countdown starts this many seconds before the rest ends.
public let countdownSeconds = 10

/// One beep of the rest countdown: a short tick with the seconds left, or the long end beep.
public enum CountdownCue: Equatable, Sendable {
    case tick(secondsLeft: Int)
    case end
}

/// A countdown beep and the time it plays.
public struct TimedCue: Equatable, Sendable {
    public let at: Date
    public let cue: CountdownCue

    public init(at: Date, cue: CountdownCue) {
        self.at = at
        self.cue = cue
    }
}

/// The beeps for a rest that ends at `endsAt`: `.tick(n)` at n = 10…1 s before the end,
/// `.end` at the end, only those after `now`. `[]` when no timer runs or it has ended.
/// A cue exactly at `now` is kept, so a 5-s rest starts with `.tick(5)` at once.
public func countdownCues(endsAt: Date?, after now: Date) -> [TimedCue] {
    guard let endsAt, endsAt > now else { return [] }
    let ticks = (1...countdownSeconds).reversed().compactMap { secondsLeft -> TimedCue? in
        let at = endsAt.addingTimeInterval(-TimeInterval(secondsLeft))
        return at >= now ? TimedCue(at: at, cue: .tick(secondsLeft: secondsLeft)) : nil
    }
    return ticks + [TimedCue(at: endsAt, cue: .end)]
}

/// The fixed notice ids, so a new plan replaces the old one.
public enum RestNoticeID {
    public static let tenLeft = "rest.ten-left"
    public static let over = "rest.over"
}

/// A local notice for the rest timer. `fireAt` nil = send now; `sound` nil = no sound.
public struct RestNotice: Equatable, Sendable {
    public let id: String
    public let fireAt: Date?
    public let title: String
    public let sound: String?

    public init(id: String, fireAt: Date?, title: String, sound: String?) {
        self.id = id
        self.fireAt = fireAt
        self.title = title
        self.sound = sound
    }
}

/// The notices for a rest that ends at `endsAt`, planned at `now`. `leavingApp` is true when
/// the app is going to the background. `[]` when no timer runs or it has ended.
///
/// - More than 10 s left: "10 seconds left" at `endsAt − 10` with `countdown_10.caf`, and
///   "Rest is over" at `endsAt`.
/// - 10 s or less, staying in the app: only "Rest is over" (the app beeps itself).
/// - 10 s or less, leaving the app: one notice now (`fireAt` nil, id `RestNoticeID.tenLeft`, so
///   it replaces the planned one) with the countdown for the seconds left, and "Rest is over".
/// "Rest is over" has no sound: the countdown sound already ends with the long beep (Q-9).
public func restNotices(endsAt: Date?, now: Date, leavingApp: Bool) -> [RestNotice] {
    guard let endsAt, endsAt > now else { return [] }
    let over = RestNotice(id: RestNoticeID.over, fireAt: endsAt, title: "Rest is over", sound: nil)
    let left = endsAt.timeIntervalSince(now)
    if left > TimeInterval(countdownSeconds) {
        let ten = RestNotice(id: RestNoticeID.tenLeft,
                             fireAt: endsAt.addingTimeInterval(-TimeInterval(countdownSeconds)),
                             title: secondsLeftTitle(countdownSeconds),
                             sound: countdownSound(secondsLeft: countdownSeconds))
        return [ten, over]
    }
    guard leavingApp else { return [over] }
    let seconds = clampedCountdown(Int(left.rounded()))
    let immediate = RestNotice(id: RestNoticeID.tenLeft, fireAt: nil, title: secondsLeftTitle(seconds),
                               sound: countdownSound(secondsLeft: seconds))
    return [immediate, over]
}

/// "10 seconds left", "1 second left".
func secondsLeftTitle(_ seconds: Int) -> String {
    seconds == 1 ? "1 second left" : "\(seconds) seconds left"
}

private func clampedCountdown(_ seconds: Int) -> Int {
    min(max(seconds, 1), countdownSeconds)
}

/// The countdown sound file for `secondsLeft`, kept in 1…10: "countdown_7.caf".
/// Each file has one short beep per second and ends with the long beep (scripts/make_sounds.py).
public func countdownSound(secondsLeft: Int) -> String {
    "countdown_\(clampedCountdown(secondsLeft)).caf"
}
