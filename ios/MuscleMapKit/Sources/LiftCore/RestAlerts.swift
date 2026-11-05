import Foundation

// Rest countdown beeps and notices (specs/lift-feedback.llm.md, AC-1 to AC-3).
// SCAFFOLD: the bodies return valid but wrong values until the build step.

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
public func countdownCues(endsAt: Date?, after now: Date) -> [TimedCue] {
    []
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
public func restNotices(endsAt: Date?, now: Date, leavingApp: Bool) -> [RestNotice] {
    []
}

/// The countdown sound file for `secondsLeft`, kept in 1…10: "countdown_7.caf".
public func countdownSound(secondsLeft: Int) -> String {
    ""
}
