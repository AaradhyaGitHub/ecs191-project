import SwiftUI
import Models
import Networking
import LiftCore
import GoalsCore

/// New goal and Edit goal. Holds no networking: `onSave` sends the body (the Goals tab's
/// model, or `APIClient.createGoal` in onboarding, #64). Every rule is in `GoalDraft`, so both
/// entry points behave the same. A refused save keeps the form open with the server's message;
/// the same id is sent again, so a retry is safe.
struct GoalFormView: View {
    /// The other active goals (leave out the one being edited), for the 3-goal limit.
    let activeCount: Int
    /// The goal being edited, or nil for a new one. Editing can't change the type or exercise.
    let editing: Goal?
    let onSave: (GoalInput) async throws -> Void
    let onCancel: () -> Void

    @State private var draft: GoalDraft
    @State private var hasDeadline: Bool
    @State private var problem: String?
    @State private var isSaving = false
    @State private var isPicking = false
    /// Made once, so Try again sends the same id.
    @State private var id: String
    @Environment(\.apiClient) private var apiClient

    private let calendar = Calendar.current
    private let startDate: Date

    init(draft: GoalDraft, activeCount: Int, editing: Goal? = nil,
         onSave: @escaping (GoalInput) async throws -> Void, onCancel: @escaping () -> Void) {
        self.activeCount = activeCount
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: draft)
        _hasDeadline = State(initialValue: draft.deadline != nil)
        _id = State(initialValue: editing?.id ?? ClientID.make())
        startDate = editing.flatMap { Self.day($0.startDate) } ?? Date()
    }

    private var errors: [GoalFormError] {
        draft.validate(startDate: startDate, activeCount: activeCount, calendar: calendar)
    }

    private var input: GoalInput? {
        guard errors.isEmpty else { return nil }
        return draft.input(id: id, startDate: startDate, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if editing == nil {
                        Picker("Goal type", selection: $draft.type) {
                            Text("Strength").tag(GoalType.strength)
                            Text("Weekly workouts").tag(GoalType.frequency)
                        }
                        .pickerStyle(.segmented)
                    }
                    switch draft.type {
                    case .strength: strengthFields
                    case .frequency: frequencyFields
                    }
                    if let shown = visibleErrorText {
                        NoticeLine(text: shown)
                    }
                    if let problem {
                        NoticeLine(text: problem)
                    }
                    PrimaryButton(title: problem == nil ? "Save" : "Try again", action: save)
                        .disabled(input == nil || isSaving)
                        .opacity(input == nil || isSaving ? 0.4 : 1)
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.m)
            }
            .background(Theme.Colors.sheet)
            .navigationTitle(editing == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .sheet(isPresented: $isPicking) {
                GoalExercisePicker(source: apiClient) { draft.exercise = $0 }
            }
            .onChange(of: draft.type) { _, _ in draft.targetText = "" }
            .onChange(of: hasDeadline) { _, on in
                draft.deadline = on ? (draft.deadline ?? startDate) : nil
            }
        }
    }

    // MARK: Fields

    private var strengthFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            label("Exercise")
            Button {
                isPicking = true
            } label: {
                HStack {
                    Text(draft.exercise?.name ?? "Pick an exercise")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(draft.exercise == nil ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    Spacer()
                    if editing == nil {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .fieldStyle()
            }
            .buttonStyle(.plain)
            .disabled(editing != nil)

            label("Target (estimated 1-rep max)")
            HStack {
                TextField("", text: $draft.targetText,
                          prompt: Text("225").foregroundStyle(Theme.Colors.textSecondary))
                    .keyboardType(.decimalPad)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(draft.unit.rawValue)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .fieldStyle()

            Toggle(isOn: $hasDeadline) {
                Text("Deadline")
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)
            if hasDeadline {
                DatePicker("By", selection: Binding(
                    get: { draft.deadline ?? startDate }, set: { draft.deadline = $0 }),
                    in: startDate..., displayedComponents: .date)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tint(Theme.Colors.accent)
            }
        }
    }

    private var frequencyFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            label("Workouts a week")
            HStack {
                TextField("", text: $draft.targetText,
                          prompt: Text("4").foregroundStyle(Theme.Colors.textSecondary))
                    .keyboardType(.numberPad)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("1 to 7")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .fieldStyle()
        }
    }

    private func label(_ text: String) -> some View {
        SectionHeader(title: text)
    }

    // MARK: Errors and saving

    /// The first rule broken, once the user has typed something (a blank form shows none).
    private var visibleErrorText: String? {
        let typed = !draft.targetText.trimmingCharacters(in: .whitespaces).isEmpty
        let shown = errors.filter { error in
            switch error {
            case .tooManyActive, .deadlineBeforeStart: true
            case .noExercise: false // the empty "Pick an exercise" row says it
            case .targetNotPositive, .frequencyOutOfRange: typed
            }
        }
        return shown.first.map(Self.text)
    }

    nonisolated static func text(_ error: GoalFormError) -> String {
        switch error {
        case .noExercise: "Pick an exercise."
        case .targetNotPositive: "Enter a weight above 0."
        case .frequencyOutOfRange: "Enter a number from 1 to 7."
        case .deadlineBeforeStart: "The deadline can't be before today."
        case .tooManyActive: "You can have 3 active goals. Finish or delete one first."
        }
    }

    private func save() {
        guard let input, !isSaving else { return }
        isSaving = true
        problem = nil
        Task {
            do {
                try await onSave(input)
            } catch {
                problem = GoalsScreenModel.message(for: error, during: .save)
            }
            isSaving = false
        }
    }

    /// Noon of a `YYYY-MM-DD` day in the phone's calendar.
    private static func day(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
    }
}

#if DEBUG
#Preview("New") {
    GoalFormView(draft: GoalDraft(unit: .lb), activeCount: 1, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    let goal = PreviewData.goals[0]
    return GoalFormView(draft: GoalDraft(editing: goal, unit: .lb), activeCount: 1, editing: goal,
                        onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}

#Preview("At the limit") {
    GoalFormView(draft: GoalDraft(unit: .lb), activeCount: 3, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}
#endif
