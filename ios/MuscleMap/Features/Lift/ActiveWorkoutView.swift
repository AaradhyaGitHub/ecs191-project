import SwiftUI
import Models
import LiftCore

/// The open workout (client_architecture.llm.md, "Lift screens", 3): the clock, the name, a
/// segmented progress bar, UP NEXT with Start, "then", DONE, and Add exercise and Finish.
/// "‹ Lift" closes the screen and keeps the workout open (the Resume card brings it back).
/// Finish calls `onFinished`; Discard does not (plan, "Starting a workout").
struct ActiveWorkoutView: View {
    let onFinished: (Workout) -> Void

    @State private var model: ActiveWorkoutModel
    @State private var path: [String] = []
    @State private var opensSheetFor: String?
    @State private var isPicking = false
    @State private var asksToDiscardEmpty = false
    @State private var finishProblem: SaveProblem?
    @State private var asksToDiscard = false
    @Environment(\.apiClient) private var apiClient
    @Environment(\.dismiss) private var dismiss

    init(session: LiftSession, onFinished: @escaping (Workout) -> Void) {
        _model = State(initialValue: ActiveWorkoutModel(session: session))
        self.onFinished = onFinished
    }

    /// Previews pass a model with data already loaded.
    init(model: ActiveWorkoutModel, onFinished: @escaping (Workout) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let active = model.active {
                    content(active)
                } else {
                    Color.clear
                }
            }
            .background(Theme.Colors.background)
            .toolbar { toolbar }
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .navigationDestination(for: String.self) { blockID in
                SetLogView(model: model, blockID: blockID, opensSheet: opensSheetFor == blockID)
            }
        }
        .task { await model.load(using: apiClient) }
        .sheet(isPresented: $isPicking) {
            ExercisePickerView(model: ExercisePickerModel(
                source: apiClient, remainingExercises: model.active?.remainingExerciseSlots ?? 0,
                unit: model.unit)) { picks in
                model.add(picks)
            }
        }
        .alert(finishProblem.map(ActiveWorkoutModel.finishText) ?? "", isPresented: Binding(
            get: { finishProblem != nil }, set: { if !$0 { finishProblem = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .alert("No sets logged. Discard this workout?", isPresented: $asksToDiscardEmpty) {
            Button("Discard", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Discard this workout?", isPresented: $asksToDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Its sets are deleted and nothing is saved.")
        }
        .sensoryFeedback(.warning, trigger: model.restEndedCount)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Label("Lift", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .foregroundStyle(Theme.Colors.accent)
        }
        ToolbarItem(placement: .principal) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(model.clock(at: context.date))
                    .font(Theme.Fonts.rowTitle.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Discard workout", systemImage: "trash", role: .destructive) { asksToDiscard = true }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minWidth: Theme.Size.minTouchTarget, minHeight: Theme.Size.minTouchTarget)
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: Content

    private func content(_ active: ActiveWorkout) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(active.name)
                            .font(Theme.Fonts.largeTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        ProgressSegments(blocks: active.blocks)
                    }
                    if let problem = model.saveProblemText {
                        NoticeLine(text: problem)
                    }
                    if let next = active.upNext {
                        upNextCard(next, active: active)
                    } else if active.blocks.isEmpty {
                        Text("Add an exercise to start.")
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let then = active.then {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            SectionHeader(title: "Then")
                            blockRow(then, detail: model.detail(of: then))
                        }
                    }
                    if !active.done.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            SectionHeader(title: "Done", count: active.done.count)
                            ForEach(active.done) { block in
                                blockRow(block, detail: model.setCountText(active.sets(in: block.id).count))
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.m)
            }
            bottomBar(active)
        }
    }

    private func upNextCard(_ block: WorkoutBlock, active: ActiveWorkout) -> some View {
        CardView(isHighlighted: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Up next")
                    .textCase(.uppercase)
                    .font(Theme.Fonts.sectionHeader)
                    .tracking(Theme.Fonts.sectionHeaderTracking)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(model.title(of: block))
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(model.detail(of: block))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                PrimaryButton(title: "Start", systemImage: "play.fill") {
                    open(block.id, sheet: active.sets(in: block.id).isEmpty)
                }
            }
        }
    }

    /// A "then" or DONE row; tapping opens its set log (a done block can take more sets).
    private func blockRow(_ block: WorkoutBlock, detail: String) -> some View {
        Button { open(block.id, sheet: false) } label: {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(model.title(of: block))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(detail)
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.m)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bottomBar(_ active: ActiveWorkout) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { isPicking = true } label: {
                Label("Add exercise", systemImage: "plus")
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButtonHeight)
                    .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            }
            .buttonStyle(.plain)
            PrimaryButton(title: "Finish", action: finish)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.border).frame(height: Theme.Size.borderWidth)
        }
    }

    // MARK: Actions

    private func open(_ blockID: String, sheet: Bool) {
        opensSheetFor = sheet ? blockID : nil
        path.append(blockID)
    }

    private func finish() {
        switch model.finish() {
        case .finished(let workout):
            onFinished(workout)
            dismiss()
        case .noSets:
            asksToDiscardEmpty = true
        case .notSaved(let problem):
            finishProblem = problem
        }
    }

    private func discard() {
        model.discard()
        dismiss()
    }
}

/// One segment per block; done blocks are filled with the accent.
private struct ProgressSegments: View {
    let blocks: [WorkoutBlock]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(blocks) { block in
                Capsule()
                    .fill(block.isDone ? Theme.Colors.accent : Theme.Colors.surfaceRaised)
                    .frame(height: Theme.Spacing.xs)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(blocks.filter(\.isDone).count) of \(blocks.count) done")
    }
}

#if DEBUG
#Preview("In progress") {
    ActiveWorkoutView(model: ActiveWorkoutModel(session: PreviewData.liftSession(withSets: true)))
        .preferredColorScheme(.dark)
}

#Preview("Just started") {
    ActiveWorkoutView(model: ActiveWorkoutModel(session: PreviewData.liftSession(withSets: false)))
        .preferredColorScheme(.dark)
}
#endif
