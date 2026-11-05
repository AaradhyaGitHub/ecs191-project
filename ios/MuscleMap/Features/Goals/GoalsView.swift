import SwiftUI
import Models
import Networking
import GoalsCore

/// Goals (#72, specs/goals.llm.md): active goal cards, New goal (disabled at 3 active), then
/// COMPLETED. Tapping a card opens its detail with Edit and Delete. Empty and error states
/// as in AC-15. Progress is worked out by the server on every load.
struct GoalsView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var model: GoalsScreenModel?
    /// The user's unit; lb until `GET /users/me` answers.
    @State private var unit: WeightUnit = .lb
    @State private var isCreating = false

    init(model: GoalsScreenModel? = nil) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Goals")
                        .font(Theme.Fonts.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let model {
                        content(model)
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.l)
            }
            .background(Theme.Colors.background)
            .refreshable { await model?.load() }
            .navigationDestination(for: Goal.self) { goal in
                if let model {
                    GoalDetailView(goal: goal, unit: unit, model: model)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if model == nil { model = GoalsScreenModel(api: apiClient) }
            await refresh()
        }
        .sheet(isPresented: $isCreating) {
            if let model {
                GoalFormView(draft: GoalDraft(unit: unit), activeCount: model.activeCount,
                             onSave: { input in
                                 try await model.create(input)
                                 isCreating = false
                             },
                             onCancel: { isCreating = false })
            }
        }
    }

    @ViewBuilder
    private func content(_ model: GoalsScreenModel) -> some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xl)
        case .empty:
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "target")
                    .font(Theme.Fonts.hero)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("No goals yet. Set one, or log a workout in Lift to see your progress.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "New goal", systemImage: "plus") { isCreating = true }
            }
            .padding(.top, Theme.Spacing.xl)
        case .failed(let message):
            VStack(spacing: Theme.Spacing.m) {
                NoticeLine(text: message)
                PrimaryButton(title: "Try again") { Task { await model.load() } }
            }
        case .loaded(let active, let completed):
            newGoalButton(model)
            if !active.isEmpty {
                cards(active)
            }
            if !completed.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: "Completed")
                    cards(completed)
                }
            }
        }
    }

    private func newGoalButton(_ model: GoalsScreenModel) -> some View {
        let isFull = model.activeCount >= GoalDraft.maxActive
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PrimaryButton(title: "New goal", systemImage: "plus") { isCreating = true }
                .disabled(isFull)
                .opacity(isFull ? 0.4 : 1)
            if isFull {
                Text("You can have 3 active goals.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func cards(_ goals: [Goal]) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(goals) { goal in
                NavigationLink(value: goal) {
                    GoalCardView(card: GoalCard(goal, unit: unit, today: model?.today ?? Date(),
                                                calendar: model?.todayCalendar ?? .current))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// On appear: the goals and the user's unit load at the same time.
    private func refresh() async {
        let client = apiClient
        async let user: User? = client.isSignedIn ? (try? await client.me()) : nil
        await model?.load()
        if let user = await user { unit = user.units }
    }
}

#if DEBUG
#Preview("Goals") {
    GoalsView(model: GoalsScreenModel(api: PreviewData.GoalsSource(), now: { PreviewData.now }))
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    GoalsView(model: GoalsScreenModel(api: PreviewData.GoalsSource(goals: []), now: { PreviewData.now }))
        .preferredColorScheme(.dark)
}

#Preview("Can't load") {
    GoalsView(model: GoalsScreenModel(api: PreviewData.GoalsSource(fails: true), now: { PreviewData.now }))
        .preferredColorScheme(.dark)
}
#endif
