import SwiftUI
import Models
import LiftCore

/// One block's sets (client_architecture.llm.md, "Lift screens", 4): filter chips in a
/// superset, the sets in the order done, the rest strip and a + button. Tap a set to edit it,
/// swipe to delete it (D-18). Done marks the block done.
struct SetLogView: View {
    let model: ActiveWorkoutModel
    let blockID: String
    /// Opens the sheet on arrival (a block with no sets, #63).
    var opensSheet = false

    @State private var filter: String?
    @State private var sheet: SetSheetRequest?
    @State private var didOpenSheet = false
    @Environment(\.dismiss) private var dismiss

    private var block: WorkoutBlock? { model.active?.block(blockID) }

    private var sets: [SetEntry] {
        let all = model.active?.sets(in: blockID) ?? []
        guard let filter else { return all }
        return all.filter { $0.exerciseId == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.saveProblemText {
                NoticeLine(text: problem)
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.top, Theme.Spacing.s)
            }
            if let block, block.exercises.count > 1 {
                chips(for: block)
            }
            list
            bottomBar
        }
        .background(Theme.Colors.background)
        .navigationTitle(block.map(model.logTitle) ?? "Sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    model.markDone(blockID)
                    dismiss()
                }
                .foregroundStyle(Theme.Colors.accent)
            }
        }
        .sheet(item: $sheet) { request in
            SetEntrySheet(request: request, unit: model.unit, onUnitChange: model.setUnit) { draft in
                model.submit(request, draft: draft)
            }
        }
        .sensoryFeedback(.warning, trigger: model.restEndedCount)
        .task {
            // Once per visit (#63). Wait for the push to finish first: a sheet presented while
            // the screen is still sliding in is sometimes dropped (seen on the Simulator).
            guard opensSheet, !didOpenSheet else { return }
            didOpenSheet = true
            try? await Task.sleep(for: .seconds(Self.pushTime))
            guard !Task.isCancelled, sheet == nil, model.active?.sets(in: blockID).isEmpty == true else { return }
            sheet = model.newSetRequest(in: blockID)
        }
    }

    /// About how long the push into this screen takes.
    private static let pushTime: TimeInterval = 0.4

    private func chips(for block: WorkoutBlock) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                Chip(title: "All", isSelected: filter == nil) { filter = nil }
                ForEach(block.exercises) { exercise in
                    Chip(title: exercise.name, isSelected: filter == exercise.id) { filter = exercise.id }
                }
            }
        }
        .contentMargins(.horizontal, Theme.Spacing.gutter, for: .scrollContent)
        .padding(.vertical, Theme.Spacing.s)
    }

    @ViewBuilder private var list: some View {
        if sets.isEmpty {
            Text("No sets yet")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(sets) { set in
                        Button { sheet = model.editRequest(for: set) } label: { row(set) }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.Colors.surface)
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.delete(set) }
                            }
                    }
                } header: {
                    Text("\(model.setCountText(sets.count)) · in the order you did them")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    /// Names on rows only when the log shows more than one exercise: a superset with the
    /// All chip on (#63).
    private var showsNames: Bool {
        (block?.exercises.count ?? 0) > 1 && filter == nil
    }

    private func row(_ set: SetEntry) -> some View {
        let all = model.active?.sets ?? []
        let name = block?.exercises.first { $0.id == set.exerciseId }?.name ?? ""
        return HStack(spacing: Theme.Spacing.m) {
            Text(logBadge(for: set, in: all))
                .font(Theme.Fonts.secondary.weight(.bold).monospacedDigit())
                .foregroundStyle(set.setType == .warmup ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .frame(width: Theme.Size.minTouchTarget * 0.7, height: Theme.Size.minTouchTarget * 0.7)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if showsNames {
                    Text(name)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(restText(for: set))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text(set.reps.map { "\($0) reps" } ?? loadText(for: set, unit: model.unit))
                    .font(Theme.Fonts.rowTitle.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
                if set.reps != nil {
                    Text(loadText(for: set, unit: model.unit))
                        .font(Theme.Fonts.secondary.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            EffortBattery(effortPct: set.effortPct)
        }
        .frame(minHeight: Theme.Size.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to edit")
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let limit = model.setLimitText {
                NoticeLine(text: limit, systemImage: "info.circle")
            }
            bottomControls
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.m)
    }

    private var bottomControls: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let timer = model.active?.restTimer, timer.isRunning {
                RestStrip(timer: timer, onAdjust: model.adjustRest, onSkip: model.skipRest)
            } else {
                Spacer()
            }
            Button { sheet = model.newSetRequest(in: blockID) } label: {
                Image(systemName: "plus")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: Theme.Size.primaryButtonHeight, height: Theme.Size.primaryButtonHeight)
                    .background(Theme.Colors.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canLog)
            .opacity(canLog ? 1 : 0.4)
            .accessibilityLabel("Log a set")
        }
    }

    private var canLog: Bool { model.active?.canLogSet ?? false }
}

#if DEBUG
#Preview("Superset with sets") {
    let model = ActiveWorkoutModel(session: PreviewData.liftSession(withSets: true),
                                   lastSets: [:])
    return NavigationStack {
        SetLogView(model: model, blockID: model.active?.blocks.first?.id ?? "")
    }
    .preferredColorScheme(.dark)
}

#Preview("No sets yet") {
    let model = ActiveWorkoutModel(session: PreviewData.liftSession(withSets: false))
    return NavigationStack {
        SetLogView(model: model, blockID: model.active?.blocks.last?.id ?? "")
    }
    .preferredColorScheme(.dark)
}
#endif
