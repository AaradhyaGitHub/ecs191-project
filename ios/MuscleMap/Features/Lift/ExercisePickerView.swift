import SwiftUI
import Models
import LiftCore

/// "New workout": search, group chips, YOUR EXERCISES and ALL EXERCISES, then
/// "Pair as superset" and the Add button (client_architecture.llm.md, "Lift screens").
/// From an open workout's "Add exercise" it is titled "Add exercises".
struct ExercisePickerView: View {
    @State private var model: ExercisePickerModel
    private let title: LocalizedStringKey
    private let onAdd: (ExerciseSelection) -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: ExercisePickerModel, title: LocalizedStringKey = "New workout",
         onAdd: @escaping (ExerciseSelection) -> Void) {
        _model = State(initialValue: model)
        self.title = title
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.m) {
                searchField
                    .padding(.horizontal, Theme.Spacing.gutter)
                groupChips
                content
                bottomBar
            }
            .padding(.top, Theme.Spacing.s)
            .background(Theme.Colors.sheet)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .task { await model.start() }
    }

    // MARK: Search and chips

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("", text: $model.text,
                      prompt: Text("Search exercises").foregroundStyle(Theme.Colors.textSecondary))
                .font(Theme.Fonts.rowTitle.weight(.regular))
                .foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !model.text.isEmpty {
                Button { model.text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: Theme.Size.minTouchTarget)
        .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                GroupChip(title: "All", isSelected: model.group == nil) { model.group = nil }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    GroupChip(title: group.name, isSelected: model.group == group) { model.group = group }
                }
            }
        }
        .contentMargins(.horizontal, Theme.Spacing.gutter, for: .scrollContent)
    }

    // MARK: Lists

    @ViewBuilder private var content: some View {
        if model.state == .failed {
            VStack(spacing: Theme.Spacing.m) {
                Text("Can't reach the server.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Try again") { model.retry() }
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Size.minTouchTarget)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if !model.myRows.isEmpty {
                        myExercisesSection
                    }
                    allExercisesSection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, Theme.Spacing.m)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder private var myExercisesSection: some View {
        HStack {
            SectionHeader(title: "Your exercises")
            SortToggle(sort: $model.sort)
        }
        ForEach(model.myRows) { row in
            PickerRow(title: row.exercise.name, subtitle: model.lastText(for: row),
                      isPicked: model.selection.contains(row.id), style: .checkbox) {
                model.selection.toggle(row.exercise)
            }
        }
        Spacer().frame(height: Theme.Spacing.m)
    }

    @ViewBuilder private var allExercisesSection: some View {
        SectionHeader(title: "All exercises")
        if let message = model.noMatchMessage {
            Text(message)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.vertical, Theme.Spacing.m)
        } else if model.results.isEmpty, model.state == .loading {
            ProgressView()
                .tint(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.l)
        }
        ForEach(model.results) { exercise in
            let parts = exerciseSubtitleParts(exercise)
            PickerRow(title: exercise.name, subtitle: parts.muscles, tag: parts.equipment,
                      isPicked: model.selection.contains(exercise.id), style: .plus) {
                model.selection.toggle(exercise)
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.m) {
            if model.selection.canSuperset {
                Toggle("Pair as superset", isOn: Binding(
                    get: { model.selection.isSuperset },
                    set: { model.selection.setSuperset($0) }))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tint(Theme.Colors.accent)
            }
            PrimaryButton(title: LocalizedStringKey(model.selection.addButtonTitle)) {
                onAdd(model.selection)
                dismiss()
            }
            .disabled(!model.canAdd)
            .opacity(model.canAdd ? 1 : 0.4)
            if let limit = model.limitText {
                Text(limit)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Colors.sheet)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.border).frame(height: Theme.Size.borderWidth)
        }
    }
}

// MARK: - Parts

private struct GroupChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.secondary.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SortToggle: View {
    @Binding var sort: MyExerciseSort

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            option("Recent", .recent)
            option("Most used", .mostUsed)
        }
        .fixedSize()
    }

    private func option(_ title: String, _ value: MyExerciseSort) -> some View {
        Button { sort = value } label: {
            Text(title)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(sort == value ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .background(sort == value ? Theme.Colors.surfaceRaised : Theme.Colors.sheet,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sort == value ? .isSelected : [])
    }
}

/// One exercise row. YOUR EXERCISES uses a checkbox; ALL EXERCISES a + that turns into a check.
private struct PickerRow: View {
    enum Style { case checkbox, plus }

    let title: String
    let subtitle: String
    /// The equipment, shown as a tag after the subtitle (#63); nil shows none.
    var tag: String? = nil
    let isPicked: Bool
    let style: Style
    let action: () -> Void

    private var icon: String {
        switch style {
        case .checkbox: isPicked ? "checkmark.square.fill" : "square"
        case .plus: isPicked ? "checkmark.circle.fill" : "plus.circle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    HStack(spacing: Theme.Spacing.s + Theme.Spacing.xs) {
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        if let tag { TagLabel(text: tag) }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(isPicked ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Signed in") {
    ExercisePickerView(model: ExercisePickerModel(
        source: PreviewExerciseSource(), now: { PreviewData.now },
        results: PreviewData.exercises, mine: PreviewData.myExercises, state: .loaded)) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Signed out") {
    ExercisePickerView(model: ExercisePickerModel(
        source: PreviewExerciseSource(isSignedIn: false), now: { PreviewData.now },
        results: PreviewData.exercises, state: .loaded)) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Workout almost full") {
    ExercisePickerView(model: ExercisePickerModel(
        source: PreviewExerciseSource(), remainingExercises: 1, now: { PreviewData.now },
        results: PreviewData.exercises, mine: PreviewData.myExercises, state: .loaded)) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Adding to an open workout") {
    ExercisePickerView(model: ExercisePickerModel(
        source: PreviewExerciseSource(), now: { PreviewData.now },
        results: PreviewData.exercises, mine: PreviewData.myExercises, state: .loaded),
                       title: "Add exercises") { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Server unreachable") {
    ExercisePickerView(model: ExercisePickerModel(
        source: PreviewExerciseSource(fails: true), state: .failed)) { _ in }
        .preferredColorScheme(.dark)
}
#endif
