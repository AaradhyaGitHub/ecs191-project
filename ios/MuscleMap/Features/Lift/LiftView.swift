import SwiftUI
import Models
import Networking
import LiftCore

/// Lift: create tiles, the open workout and the outbox. The "Empty workout" tile opens the
/// exercise picker; its Add starts the workout (`LiftSession.start`). While a workout is open,
/// a Resume card shows it and Empty workout is disabled (D-16). Finished workouts that aren't
/// on the server yet show in a banner (plan, "Empty and error states").
/// Saved workouts (#43) follow CREATE: Start opens one through `LiftSession.start`, and Finish
/// offers "Save as a workout" (specs/saved-workouts.llm.md).
struct LiftView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(LiftSession.self) private var session
    @State private var isPicking = false
    @State private var showsWorkout = false
    /// Set by the picker's Add; the workout opens once the picker has closed.
    @State private var opensAfterPicker = false
    @State private var deleting: OutboxItem?
    /// The user's unit for the picker; lb until `GET /users/me` answers.
    @State private var unit: WeightUnit = .lb
    /// Saved workouts (#43); made on first appear with the shared API client.
    @State private var saved: SavedWorkoutsModel?
    /// Finish on the Resume card (#63): the confirm, then the same alerts as inside the workout.
    @State private var asksToFinish = false
    /// What Finish did, shown once the confirm alert has closed (review S1).
    @State private var afterConfirm: FinishResult?
    @State private var asksToDiscardEmpty = false
    @State private var finishProblem: SaveProblem?

    init(saved: SavedWorkoutsModel? = nil) {
        _saved = State(initialValue: saved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Lift")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if session.storageIsTemporary {
                    NoticeLine(text: "Workouts can't be saved on this phone right now.")
                }
                OutboxBanner(outbox: session.outbox) { deleting = $0 }
                if let active = session.active {
                    resumeCard(active)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: "Create")
                    emptyWorkoutTile
                    CustomPlanTile()
                }
                if let saved {
                    SavedWorkoutsSection(model: saved, isStartDisabled: session.isWorkoutOpen,
                                         onStart: open)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.l)
        }
        .background(Theme.Colors.background)
        .refreshable { await saved?.load() }
        .task {
            if saved == nil { saved = SavedWorkoutsModel(source: apiClient) }
            await refresh()
        }
        .sheet(isPresented: $isPicking, onDismiss: {
            if opensAfterPicker {
                opensAfterPicker = false
                showsWorkout = true
            }
        }) {
            ExercisePickerView(model: ExercisePickerModel(source: apiClient, unit: unit), onAdd: start)
        }
        .fullScreenCover(isPresented: $showsWorkout, onDismiss: { saved?.showPendingOffer() }) {
            ActiveWorkoutView(session: session) { saved?.finished($0) }
        }
        .sheet(item: Binding(get: { saved?.offer }, set: { if $0 == nil { saved?.dismissOffer() } })) { workout in
            if let saved { SaveAsWorkoutSheet(workout: workout, model: saved) }
        }
        .confirmationDialog("Delete this workout?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible,
            presenting: deleting) { item in
            Button("Delete", role: .destructive) { session.outbox.delete(id: item.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It was not saved on the server. Deleting it can't be undone.")
        }
        .alert("Finish this workout?", isPresented: $asksToFinish) {
            Button("Finish", action: finishOpenWorkout)
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: asksToFinish) { _, isShown in
            if !isShown { showAfterConfirm() }
        }
        .alert("No sets logged. Discard this workout?", isPresented: $asksToDiscardEmpty) {
            Button("Discard", role: .destructive) { session.discard() }
            Button("Keep going", role: .cancel) {}
        }
        .alert(finishProblem.map(ActiveWorkoutModel.finishText) ?? "", isPresented: Binding(
            get: { finishProblem != nil }, set: { if !$0 { finishProblem = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Finish on the Resume card (#63). With no sets it asks only "Discard this workout?"
    /// (Sasa, Nov 4, 2026); otherwise it asks "Finish this workout?" first.
    private func askToFinish(_ active: ActiveWorkout) {
        afterConfirm = nil
        if active.sets.isEmpty {
            asksToDiscardEmpty = true
        } else {
            asksToFinish = true
        }
    }

    /// The confirm's Finish does what Finish inside the workout does. What comes next (the
    /// "Save as a workout" sheet or an alert) waits until the confirm alert has closed.
    private func finishOpenWorkout() {
        let result = ActiveWorkoutModel(session: session).finish()
        if case .finished(let workout) = result { saved?.finished(workout) }
        afterConfirm = result
        // SwiftUI may close the alert before or after running this action.
        if !asksToFinish { showAfterConfirm() }
    }

    private func showAfterConfirm() {
        guard let result = afterConfirm else { return }
        afterConfirm = nil
        switch result {
        case .finished: saved?.showPendingOffer()
        case .noSets: asksToDiscardEmpty = true
        case .notSaved(let problem): finishProblem = problem
        }
    }

    /// "Add" in the picker: a new workout with the picks, opened at once.
    private func start(_ picks: ExerciseSelection) {
        var workout = ActiveWorkout(startedAt: Date())
        workout.add(picks.picked, asSuperset: picks.isSuperset)
        if session.start(workout) {
            opensAfterPicker = true
        }
    }

    /// On appear: the upload, the saved workouts and the user's unit load at the same time,
    /// the upload started first; none waits for another (review S-4, Sasa, Nov 4, 2026).
    private func refresh() async {
        let outbox = session.outbox
        let model = saved
        let client = apiClient
        async let upload: Void = outbox.sendPending()
        async let templates: Void? = model?.load()
        async let user: User? = client.isSignedIn ? (try? await client.me()) : nil
        if let user = await user { unit = user.units }
        _ = await (upload, templates)
    }

    /// Start on a saved workout: opens the workout it made (disabled while one is open, D18).
    private func open(_ workout: ActiveWorkout) {
        if session.start(workout) { showsWorkout = true }
    }

    /// The open workout: name and clock, then Resume and Finish (#63).
    private func resumeCard(_ active: ActiveWorkout) -> some View {
        CardView(isHighlighted: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Resume workout")
                            .textCase(.uppercase)
                            .font(Theme.Fonts.sectionHeader)
                            .tracking(Theme.Fonts.sectionHeaderTracking)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(active.name)
                            .font(Theme.Fonts.cardTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(workoutClockText(since: active.startedAt, at: context.date))
                            .font(Theme.Fonts.secondary.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                HStack(spacing: Theme.Spacing.s) {
                    cardButton("Resume", isPrimary: true) {
                        afterConfirm = nil
                        showsWorkout = true
                    }
                    cardButton("Finish", isPrimary: false) { askToFinish(active) }
                }
            }
        }
    }

    private func cardButton(_ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.rowTitle.weight(.bold))
                .foregroundStyle(isPrimary ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
                .background(isPrimary ? Theme.Colors.accent : Theme.Colors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
        }
        .buttonStyle(.plain)
    }

    private var emptyWorkoutTile: some View {
        Button { isPicking = true } label: {
            CardView {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "plus")
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Empty workout")
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Add exercises as you go")
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(session.isWorkoutOpen)
        .opacity(session.isWorkoutOpen ? 0.4 : 1)
    }
}

/// "1 workout not uploaded yet" with Try again; a rejected one shows the server's message
/// with Try again and Delete (D-17).
private struct OutboxBanner: View {
    let outbox: WorkoutOutbox
    let onDelete: (OutboxItem) -> Void

    var body: some View {
        let waiting = outbox.pending.count
        let rejected = outbox.items.filter(\.isRejected)
        if waiting > 0 || !rejected.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if waiting > 0 {
                    CardView {
                        HStack {
                            Image(systemName: "icloud.slash")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(waiting == 1 ? "1 workout not uploaded yet" : "\(waiting) workouts not uploaded yet")
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            tryAgain { await outbox.sendPending() }
                        }
                    }
                }
                ForEach(rejected) { item in
                    CardView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text(item.workout.name)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Couldn't save: \(item.rejectedMessage ?? "")")
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: Theme.Spacing.m) {
                                tryAgain { await outbox.retry(id: item.id) }
                                Button("Delete", role: .destructive) { onDelete(item) }
                                    .font(Theme.Fonts.secondary.weight(.semibold))
                                    .frame(minHeight: Theme.Size.minTouchTarget)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tryAgain(_ action: @escaping () async -> Void) -> some View {
        Button("Try again") { Task { await action() } }
            .font(Theme.Fonts.secondary.weight(.semibold))
            .foregroundStyle(Theme.Colors.accent)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .disabled(outbox.isSending)
    }
}

#if DEBUG
#Preview("Start") {
    LiftView()
        .environment(PreviewData.liftSession(open: false))
        .preferredColorScheme(.dark)
}

#Preview("Saved workouts") {
    LiftView(saved: .preview())
        .environment(PreviewData.liftSession(open: false))
        .preferredColorScheme(.dark)
}

#Preview("Workout open, one not uploaded") {
    LiftView()
        .environment(PreviewData.liftSession(withSets: true, outboxed: 1))
        .preferredColorScheme(.dark)
}
#endif
