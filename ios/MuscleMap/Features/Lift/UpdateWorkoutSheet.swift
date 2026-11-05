import SwiftUI
import Models
import LiftCore

/// After Finish, for a changed workout that started from a saved workout (#67, AC-10):
/// "Update '<name>' with your changes?" with Update, Save as new and Not now. Update keeps the
/// name and focus. If the server fails, the sheet stays open with the error and Try again;
/// Not now drops the changes (Q-5). Save as new opens the "Save as a workout" sheet.
struct UpdateWorkoutSheet: View {
    let template: Template
    let workout: ActiveWorkout
    let model: SavedWorkoutsModel

    @State private var problem: String?
    @State private var isSaving = false
    /// The content's height; the sheet is only this tall. Grows when the error line shows.
    @State private var contentHeight: CGFloat = 320
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Update '\(template.name)' with your changes?")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                NoticeLine(text: problem)
            }
            VStack(spacing: Theme.Spacing.s) {
                PrimaryButton(title: problem == nil ? "Update" : "Try again", action: update)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.4 : 1)
                Button { model.saveAsNew() } label: {
                    Text("Save as new")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButtonHeight)
                        .background(Theme.Colors.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                Button("Not now") {
                    model.dismissOffer()
                    dismiss()
                }
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
                .disabled(isSaving)
            }
        }
        .padding(Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.s)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.sheet)
        .presentationDetents([.height(contentHeight)])
        .presentationBackground(Theme.Colors.sheet)
        .interactiveDismissDisabled(isSaving)
    }

    private func update() {
        isSaving = true
        Task {
            problem = await model.update(template, from: workout)
            isSaving = false
            if problem == nil { dismiss() }
        }
    }
}

#if DEBUG
#Preview("Presented over Lift") {
    LiftView(saved: .preview())
        .environment(PreviewData.liftSession(open: false))
        .sheet(isPresented: .constant(true)) {
            UpdateWorkoutSheet(template: PreviewData.push, workout: PreviewData.changedPush, model: .preview())
        }
        .preferredColorScheme(.dark)
}

#Preview("Update question") {
    UpdateWorkoutSheet(template: PreviewData.push, workout: PreviewData.changedPush, model: .preview())
        .preferredColorScheme(.dark)
}

#Preview("Update failed") {
    UpdateWorkoutSheet(template: PreviewData.push, workout: PreviewData.changedPush,
                       model: .preview(fails: true))
        .preferredColorScheme(.dark)
}
#endif
