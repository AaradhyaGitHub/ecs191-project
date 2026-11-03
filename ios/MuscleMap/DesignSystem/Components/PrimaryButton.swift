import SwiftUI

/// The main call to action: accent fill, onAccent text, 52 pt tall, full width.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Theme.Fonts.rowTitle.weight(.bold))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButtonHeight)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        PrimaryButton(title: "Log 6 × 155 lb") {}
        PrimaryButton(title: "Start", systemImage: "play.fill") {}
    }
    .padding(Theme.Spacing.gutter)
    .frame(maxHeight: .infinity)
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
