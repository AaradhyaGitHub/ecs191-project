import Foundation
import Models

// Texts in the set log and the set sheet (plan: specs/log-workout.llm.md, "Rules";
// client_architecture.llm.md, "Lift screens").

/// A number without a trailing ".0": 155 → "155", 2.5 → "2.5", 1.25 → "1.25".
public func numberText(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%g", rounded)
}

/// A weight in `unit`, rounded for display to the nearest 0.5: "220.5", "100".
/// Storage keeps exact kg; only this text rounds (D-14).
public func weightNumberText(_ weight: Weight, unit: WeightUnit) -> String {
    numberText((weight.value(in: unit) * 2).rounded() / 2)
}

/// "155 lb", "100 kg".
public func weightText(_ weight: Weight, unit: WeightUnit) -> String {
    "\(weightNumberText(weight, unit: unit)) \(unit.rawValue)"
}

/// "BW", "BW +10 lb", "BW −20 lb" (assisted).
public func bodyweightText(addedLoad: Weight, unit: WeightUnit) -> String {
    let shown = (addedLoad.value(in: unit) * 2).rounded() / 2
    if shown == 0 { return "BW" }
    let sign = shown > 0 ? "+" : "\u{2212}"
    return "BW \(sign)\(weightText(Weight(abs(shown), unit), unit: unit))"
}

/// The row badge: "W" for a warm-up, "F" for failure, else the set's number among that
/// exercise's non-warm-up sets in `sets` ("2").
public func badge(for set: SetEntry, in sets: [SetEntry]) -> String {
    switch set.setType {
    case .warmup: return "W"
    case .failure: return "F"
    case .working, .dropset:
        let numbered = sets
            .filter { $0.exerciseId == set.exerciseId && $0.setType != .warmup }
            .sorted { $0.order < $1.order }
        let index = numbered.firstIndex { $0.id == set.id } ?? numbered.count
        return String(index + 1)
    }
}

/// The load column: "BW", "BW +10 lb", "155 lb", "45 s". Weights in `unit`, rounded for display.
public func loadText(for set: SetEntry, unit: WeightUnit) -> String {
    if let kg = set.weightKg {
        return weightText(Weight(kilograms: kg), unit: unit)
    }
    if let seconds = set.durationS, set.reps == nil {
        return "\(seconds) s"
    }
    return bodyweightText(addedLoad: Weight(kilograms: set.addedLoadKg ?? 0), unit: unit)
}

/// The sheet's primary button: "Log 6 × 155 lb".
public func logButtonTitle(for draft: SetDraft, unit: WeightUnit) -> String {
    switch entryKind(for: draft.loadType) {
    case .plates, .perDumbbell, .weight:
        return "Log \(draft.reps) × \(weightText(draft.weight, unit: unit))"
    case .bodyweight:
        return "Log \(draft.reps) × \(bodyweightText(addedLoad: draft.addedLoad, unit: unit))"
    case .seconds:
        return "Log \(draft.durationS) s"
    }
}

/// "2:30" for 150 seconds.
public func clockText(seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// The workout clock: time since `start`, "12:34", or "1:02:03" after an hour. Shared by the
/// workout screen and Lift's Resume card.
public func workoutClockText(since start: Date, at date: Date) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(start)))
    if seconds < 3600 { return clockText(seconds: seconds) }
    return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
}

/// The rest column: "2:30 rest", or "First set · 6:02 PM" for a set with no rest before it
/// (the time is its `endedAt` in `timeZone`).
public func restText(for set: SetEntry, timeZone: TimeZone = .current) -> String {
    if let rest = set.restBeforeS {
        return "\(clockText(seconds: rest)) rest"
    }
    guard let ended = set.endedAt else { return "First set" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "h:mm a"
    return "First set · \(formatter.string(from: ended))"
}
