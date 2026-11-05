import SwiftUI
import Models
import LiftCore

/// Picks the one exercise of a strength goal. Uses Lift's search (`ExerciseSearch`), and
/// hides bodyweight and timed exercises, which can't be strength goals (Decided 2).
struct GoalExercisePicker: View {
    let onPick: (Exercise) -> Void

    @State private var search: ExerciseSearch
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    init(source: any ExerciseSource, onPick: @escaping (Exercise) -> Void) {
        _search = State(initialValue: ExerciseSearch(source: source))
        self.onPick = onPick
    }

    private var exercises: [Exercise] {
        search.results.filter { $0.loadType != .bodyweight && $0.loadType != .timed }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.m) {
                searchField
                    .padding(.horizontal, Theme.Spacing.gutter)
                content
            }
            .padding(.top, Theme.Spacing.s)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.sheet)
            .navigationTitle("Pick an exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.sheet, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .task { search.search("", group: nil, after: .zero) }
        .onChange(of: text) { _, new in search.search(new, group: nil, after: ExerciseSearch.typingDelay) }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("", text: $text,
                      prompt: Text("Search exercises").foregroundStyle(Theme.Colors.textSecondary))
                .font(Theme.Fonts.rowTitle.weight(.regular))
                .foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: Theme.Size.minTouchTarget)
        .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
    }

    @ViewBuilder
    private var content: some View {
        if search.state == .failed {
            VStack(spacing: Theme.Spacing.m) {
                NoticeLine(text: "Can't reach the server.")
                Button("Try again") { search.search(text, group: nil, after: .zero) }
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.horizontal, Theme.Spacing.gutter)
        } else if search.state == .loading && exercises.isEmpty {
            ProgressView().tint(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.l)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(exercises) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            row(exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(exercise.name)
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(exerciseSubtitle(exercise))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    GoalExercisePicker(source: PreviewExerciseSource()) { _ in }
        .preferredColorScheme(.dark)
}
#endif
