import SwiftUI
import Models
import LiftCore

/// SAVED WORKOUTS · n on Lift home (plan: specs/saved-workouts.llm.md, "What the user sees"):
/// the cards with UP NEXT first, and the empty, error and no-token states. A long press on a
/// card offers Rename and Delete (D11). Start is disabled while a workout is open (D18).
struct SavedWorkoutsSection: View {
    let model: SavedWorkoutsModel
    let isStartDisabled: Bool
    /// Opens the workout that Start made (`LiftSession.start`).
    let onStart: (ActiveWorkout) -> Void

    @State private var renaming: Template?
    @State private var newName = ""
    @State private var newFocus = ""
    @State private var renameError: String?
    @State private var showsRename = false
    @State private var deleting: Template?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Saved workouts", count: model.state == .loaded ? model.templates.count : nil)
            if let errorText = model.errorText {
                NoticeLine(text: errorText)
            }
            content
        }
        .alert(renameError == nil ? "Rename" : "Couldn't rename", isPresented: $showsRename,
               presenting: renaming) { template in
            TextField("Name", text: $newName)
            TextField("Focus (optional)", text: $newFocus)
            Button(renameError == nil ? "Save" : "Try again") { rename(template) }
                .disabled(cleanName(newName) == nil)
            Button("Cancel", role: .cancel) { renameError = nil }
        } message: { _ in
            if let renameError { Text(renameError) }
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible,
            presenting: deleting) { template in
            Button("Delete", role: .destructive) { Task { await model.delete(template) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your past workouts stay.")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .signedOut:
            messageCard("Sign in to see your saved workouts.")
        case .loading:
            ProgressView()
                .tint(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButtonHeight)
        case .failed:
            CardView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Couldn't load your saved workouts.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Button("Try again") { Task { await model.load() } }
                        .font(Theme.Fonts.secondary.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minHeight: Theme.Size.minTouchTarget)
                }
            }
        case .loaded:
            if model.templates.isEmpty {
                messageCard("No saved workouts yet. Finish a workout, then save it to start it again with one tap.")
            } else {
                cards
            }
        }
    }

    private var cards: some View {
        let upNext = model.upNext
        let now = model.now()
        return VStack(spacing: Theme.Spacing.m) {
            ForEach(model.cards) { template in
                SavedWorkoutCard(template: template, isUpNext: template.id == upNext, now: now,
                                 isStartDisabled: isStartDisabled) {
                    onStart(model.workout(for: template))
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { askRename(template) }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = template }
                }
            }
        }
    }

    private func messageCard(_ text: String) -> some View {
        CardView {
            Text(text)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: Actions

    private func askRename(_ template: Template) {
        renaming = template
        newName = template.name
        newFocus = template.focus ?? ""
        renameError = nil
        showsRename = true
    }

    /// The alert closes on any tap; if the server fails it opens again with the error and
    /// Try again, keeping what was typed. It waits for the closing alert to leave first, because
    /// SwiftUI ignores a new alert while the old one is still animating out.
    private func rename(_ template: Template) {
        Task {
            let started = Date()
            renameError = await model.rename(template, name: newName, focus: newFocus)
            guard renameError != nil, model.state != .signedOut else { return }
            let left = Self.alertCloseTime - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            showsRename = true
        }
    }

    /// About how long an alert takes to animate out.
    private static let alertCloseTime: TimeInterval = 0.5
}

/// "Custom plan · A multi-week program" with a "Soon" pill; disabled until programs exist.
struct CustomPlanTile: View {
    var body: some View {
        CardView {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "calendar")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Custom plan")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("A multi-week program")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text("Soon")
                    .font(Theme.Fonts.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.surfaceRaised, in: Capsule())
            }
        }
        .opacity(0.4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Custom plan, a multi-week program. Coming soon.")
    }
}

#if DEBUG
private struct SectionPreview: View {
    let model: SavedWorkoutsModel
    var body: some View {
        ScrollView {
            SavedWorkoutsSection(model: model, isStartDisabled: false) { _ in }
                .padding(Theme.Spacing.gutter)
        }
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
    }
}

#Preview("Cards") { SectionPreview(model: .preview()) }
#Preview("Empty") { SectionPreview(model: .preview(templates: [])) }
#Preview("Couldn't load") { SectionPreview(model: .preview(.failed, templates: [])) }
#Preview("List with an error line") {
    SectionPreview(model: .preview(errorText: "Couldn't delete Push 1. Try again."))
}
#Preview("No token") { SectionPreview(model: .preview(.signedOut, templates: [], signedIn: false)) }
#Preview("Custom plan tile") {
    CustomPlanTile()
        .padding(Theme.Spacing.gutter)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
