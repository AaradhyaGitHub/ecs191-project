import Foundation
import Models

// Texts in the set log and the set sheet (plan: specs/log-workout.llm.md, "Rules";
// client_architecture.llm.md, "Lift screens").
// SCAFFOLD: the functions return valid but wrong values. Build mode fills them in.

/// The row badge: "W" for a warm-up, "F" for failure, else the set's number among that
/// exercise's non-warm-up sets in `sets` ("2").
public func badge(for set: SetEntry, in sets: [SetEntry]) -> String {
    ""
}

/// The load column: "BW", "BW +10 lb", "155 lb", "45 s". Weights in `unit`, rounded for display.
public func loadText(for set: SetEntry, unit: WeightUnit) -> String {
    ""
}

/// The sheet's primary button: "Log 6 × 155 lb".
public func logButtonTitle(for draft: SetDraft, unit: WeightUnit) -> String {
    ""
}

/// The rest column: "2:30 rest", or "First set · 6:02 PM" for a set with no rest before it
/// (the time is its `endedAt` in `timeZone`).
public func restText(for set: SetEntry, timeZone: TimeZone = .current) -> String {
    ""
}
