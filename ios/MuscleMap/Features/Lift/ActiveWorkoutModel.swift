import Foundation
import Observation
import Models
import Networking
import LiftCore

/// What the workout screens need from the server: units and body weight (`GET /users/me`),
/// the lb/kg switch (`PUT /users/me`, D-14) and each exercise's last set (`GET /exercises/mine`).
/// `APIClient` in the app; a stub in previews.
protocol LiftProfileSource: Sendable {
    var isSignedIn: Bool { get }
    func me() async throws -> User
    func updateMe(_ update: UserUpdate) async throws -> User
    func myExercises() async throws -> [UserExercise]
}

extension APIClient: LiftProfileSource {}

/// The set sheet's input: which block and exercise, the start values, and the set being
/// edited (nil for a new set).
struct SetSheetRequest: Identifiable {
    let id = UUID()
    let blockID: String
    let exercise: Exercise
    var draft: SetDraft
    let editing: SetEntry?
    /// "Same as last set": this exercise's last set in this workout, else the server's.
    let lastSet: LastSet?
    /// The number in the sheet's title ("Set 3").
    let number: String
}

/// The open workout's screens (plan: specs/log-workout.llm.md). The rules live in LiftCore;
/// this class adds the server calls, the clock and the rest-end vibration.
@MainActor
@Observable
final class ActiveWorkoutModel {
    let session: LiftSession

    /// lb until `GET /users/me` answers (plan, "lb/kg").
    private(set) var unit: WeightUnit = .lb
    /// Each exercise's last set from `GET /exercises/mine`, for pre-fill.
    private(set) var lastSets: [String: LastSet] = [:]
    /// Goes up by one when a rest timer reaches 0 while the app is open (the vibration).
    private(set) var restEndedCount = 0

    @ObservationIgnored private var source: (any LiftProfileSource)?
    @ObservationIgnored private var restTask: Task<Void, Never>?

    init(session: LiftSession, unit: WeightUnit = .lb, lastSets: [String: LastSet] = [:]) {
        self.session = session
        self.unit = unit
        self.lastSets = lastSets
    }

    var active: ActiveWorkout? { session.active }

    // MARK: Loading

    /// Units, body weight and last sets. Each is optional: without them the defaults apply.
    func load(using source: any LiftProfileSource) async {
        self.source = source
        scheduleRestEnd()
        guard source.isSignedIn else { return }
        if let user = try? await source.me() {
            unit = user.units
            if let kg = user.bodyweightKg, session.active?.bodyweightKg == nil {
                session.update { $0.bodyweightKg = kg }
            }
        }
        if let mine = try? await source.myExercises() {
            lastSets = Dictionary(mine.compactMap { row in row.lastSet.map { (row.exerciseId, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        }
    }

    /// The lb/kg switch changes the whole app's unit (D-14).
    func setUnit(_ newUnit: WeightUnit) {
        guard newUnit != unit else { return }
        unit = newUnit
        guard let source, source.isSignedIn else { return }
        Task { _ = try? await source.updateMe(UserUpdate(units: newUnit)) }
    }

    // MARK: Texts

    /// "Push-up + Inverted Row".
    func title(of block: WorkoutBlock) -> String {
        block.exercises.map(\.name).joined(separator: " + ")
    }

    /// The set log's title: the exercise, or "Superset A".
    func logTitle(of block: WorkoutBlock) -> String {
        if let group = block.supersetGroup { return "Superset \(group.uppercased())" }
        return block.exercises.first?.name ?? "Sets"
    }

    /// The UP NEXT card's line: "Round 2 · rest 90 s after round", "Set 2 of 4", "3 sets".
    func detail(of block: WorkoutBlock) -> String {
        guard let active else { return "" }
        if block.isSuperset {
            let rest = block.restS ?? SetDraft.defaultRestS
            return "Round \(active.round(in: block.id)) · rest \(rest) s after round"
        }
        let count = active.sets(in: block.id).filter { $0.setType != .warmup }.count
        if let target = block.targetSets {
            return "Set \(min(count + 1, target)) of \(target)"
        }
        return setCountText(active.sets(in: block.id).count)
    }

    /// The line in the set log when Log is disabled at 300 sets (D-26).
    var setLimitText: String? {
        guard let active, !active.canLogSet else { return nil }
        return "A workout can have up to \(ActiveWorkout.maxSets) sets."
    }

    func setCountText(_ count: Int) -> String {
        count == 0 ? "No sets yet" : count == 1 ? "1 set" : "\(count) sets"
    }

    /// The workout clock: "12:34", or "1:02:03" after an hour.
    func clock(at date: Date) -> String {
        guard let start = active?.startedAt else { return "0:00" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        if seconds < 3600 { return clockText(seconds: seconds) }
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    // MARK: The set sheet

    /// A new set for the block's next exercise (A, B, A, B… in a superset).
    func newSetRequest(in blockID: String) -> SetSheetRequest? {
        guard let active, active.canLogSet, let exercise = active.nextExercise(in: blockID) else { return nil }
        let draft = SetDraft.prefill(for: exercise, block: active.block(blockID), previous: active.sets,
                                     lastSet: lastSets[exercise.id], unit: unit)
        let earlier = active.sets.filter { $0.exerciseId == exercise.id && $0.setType != .warmup }
        return SetSheetRequest(blockID: blockID, exercise: exercise, draft: draft, editing: nil,
                               lastSet: lastSet(for: exercise.id), number: String(earlier.count + 1))
    }

    /// Editing a logged set (tap a row, D-18).
    func editRequest(for set: SetEntry) -> SetSheetRequest? {
        guard let active, let blockID = active.blockIDBySet[set.id], let block = active.block(blockID),
              let exercise = block.exercises.first(where: { $0.id == set.exerciseId }) else { return nil }
        let draft = SetDraft(exerciseId: exercise.id, loadType: exercise.loadType, setType: set.setType,
                             reps: set.reps ?? SetDraft.defaultReps,
                             durationS: set.durationS ?? SetDraft.defaultDurationS,
                             weight: Weight(kilograms: set.weightKg ?? 0),
                             addedLoad: Weight(kilograms: set.addedLoadKg ?? 0),
                             effortPct: set.effortPct ?? SetDraft.defaultEffortPct,
                             restAfterS: block.restS ?? SetDraft.defaultRestS)
        return SetSheetRequest(blockID: blockID, exercise: exercise, draft: draft, editing: set,
                               lastSet: nil, number: badge(for: set, in: active.sets))
    }

    private func lastSet(for exerciseID: String) -> LastSet? {
        let here = active?.sets.filter { $0.exerciseId == exerciseID }.max { $0.order < $1.order }
        return here.map(LastSet.init(of:)) ?? lastSets[exerciseID]
    }

    /// Log (or save an edit) from the sheet. A new set starts the rest timer, except between
    /// the exercises of a superset round (D-11).
    func submit(_ request: SetSheetRequest, draft: SetDraft, at date: Date = Date()) {
        if let old = request.editing {
            let edited = draft.entry(id: old.id, order: old.order)
            session.update { $0.update(edited) }
            return
        }
        session.update { workout in
            let set = workout.log(draft, in: request.blockID, at: date)
            if workout.startsRest(after: set) {
                workout.startRest(seconds: draft.restAfterS, at: date)
            }
        }
        scheduleRestEnd()
    }

    func delete(_ set: SetEntry) {
        session.update { $0.delete(setID: set.id) }
    }

    // MARK: Blocks

    /// "Add exercise": the picks go at the end. False when they would go over 30 (D-23).
    @discardableResult
    func add(_ selection: ExerciseSelection) -> Bool {
        var added = false
        session.update { added = $0.add(selection.picked, asSuperset: selection.isSuperset) }
        return added
    }

    func markDone(_ blockID: String) {
        session.update { $0.markDone(blockID: blockID) }
    }

    // MARK: Rest timer

    func adjustRest(by seconds: Int) {
        session.update { $0.adjustRest(by: seconds, at: Date()) }
        scheduleRestEnd()
    }

    func skipRest() {
        session.update { $0.skipRest() }
        scheduleRestEnd()
    }

    /// Waits for the timer's end time and then bumps `restEndedCount`, so the view vibrates.
    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let endsAt = active?.restTimer.endsAt, endsAt > Date() else { return }
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled, let self, self.active?.restTimer.endsAt == endsAt else { return }
            self.restEndedCount += 1
        }
    }

    // MARK: Finish

    /// Moves the workout to the outbox and starts sending it. Anything but `.finished` leaves
    /// the workout open.
    func finish(at date: Date = Date()) -> FinishResult {
        let result = session.finishResult(at: date)
        if case .finished = result {
            restTask?.cancel()
            let outbox = session.outbox
            Task { await outbox.sendPending() }
        }
        return result
    }

    /// The alert when Finish couldn't save the workout on the phone.
    static func finishText(_ problem: SaveProblem) -> String {
        switch problem {
        case .storageFailed: "Couldn't save this workout on your phone. Free some space and tap Finish again."
        case .outOfRange: "A value in this workout is out of range. Check its sets and tap Finish again."
        }
    }

    /// The line on the workout screens when the last change wasn't saved on the phone.
    var saveProblemText: String? {
        switch session.saveProblem {
        case .storageFailed?: "Couldn't save on your phone. Free some space."
        case .outOfRange?: "A value is out of range, so the change wasn't saved."
        case nil: nil
        }
    }

    func discard() {
        restTask?.cancel()
        session.discard()
    }
}

#if DEBUG
/// A stand-in server for previews.
struct PreviewLiftSource: LiftProfileSource {
    var isSignedIn = true
    func me() async throws -> User { PreviewData.user }
    func updateMe(_ update: UserUpdate) async throws -> User { PreviewData.user }
    func myExercises() async throws -> [UserExercise] { PreviewData.myExercises }
}
#endif
