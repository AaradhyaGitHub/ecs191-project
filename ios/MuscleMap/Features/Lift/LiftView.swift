import SwiftUI
import Models
import Networking
import LiftCore

/// Lift: create tiles, the open workout and the outbox. The "Empty workout" tile opens the
/// exercise picker; its Add starts the workout (`LiftSession.start`). While a workout is open,
/// a Resume card shows it and Empty workout is disabled (D-16). Finished workouts that aren't
/// on the server yet show in a banner (plan, "Empty and error states").
struct LiftView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(LiftSession.self) private var session
    @State private var isPicking = false
    @State private var showsWorkout = false
    /// Set by the picker's Add; the workout opens once the picker has closed.
    @State private var opensAfterPicker = false
    @State private var deleting: OutboxItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Lift")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                OutboxBanner(outbox: session.outbox) { deleting = $0 }
                if let active = session.active {
                    resumeCard(active)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: "Create")
                    emptyWorkoutTile
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, Theme.Spacing.l)
        }
        .background(Theme.Colors.background)
        .task { await session.outbox.sendPending() }
        .sheet(isPresented: $isPicking, onDismiss: {
            if opensAfterPicker {
                opensAfterPicker = false
                showsWorkout = true
            }
        }) {
            ExercisePickerView(model: ExercisePickerModel(source: apiClient), onAdd: start)
        }
        .fullScreenCover(isPresented: $showsWorkout) {
            ActiveWorkoutView(session: session) { _ in }
        }
        .confirmationDialog("Delete this workout?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible,
            presenting: deleting) { item in
            Button("Delete", role: .destructive) { session.outbox.delete(id: item.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It was not saved on the server. Deleting it can't be undone.")
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

    private func resumeCard(_ active: ActiveWorkout) -> some View {
        CardView(isHighlighted: true) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Resume workout")
                        .textCase(.uppercase)
                        .font(Theme.Fonts.sectionHeader)
                        .tracking(Theme.Fonts.sectionHeaderTracking)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(active.name)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(since: active.startedAt, at: context.date))
                            .font(Theme.Fonts.secondary.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                Button { showsWorkout = true } label: {
                    Text("Resume")
                        .font(Theme.Fonts.rowTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(minHeight: Theme.Size.minTouchTarget)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func elapsed(since start: Date, at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        if seconds < 3600 { return clockText(seconds: seconds) }
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
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

#Preview("Workout open, one not uploaded") {
    LiftView()
        .environment(PreviewData.liftSession(withSets: true, outboxed: 1))
        .preferredColorScheme(.dark)
}
#endif
