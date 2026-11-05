import SwiftUI

/// The layout every onboarding screen shares: title and note at the top, the screen's own
/// content, then its buttons at the bottom, above the keyboard.
struct OnboardingPage<Content: View, Buttons: View>: View {
    let title: String
    var message: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(title)
                            .font(Theme.Fonts.largeTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let message {
                            Text(message)
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    content
                }
                .padding(.top, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: Theme.Spacing.s) {
                buttons
            }
            .padding(.bottom, Theme.Spacing.m)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

/// A caps label over a field or chip row, like "UNITS".
struct OnboardingLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(Theme.Fonts.sectionHeader)
            .tracking(Theme.Fonts.sectionHeaderTracking)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// The boxed look of an onboarding text field (same as the Lift sheets' fields).
struct OnboardingFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.rowTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.Size.primaryButtonHeight)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.smallButton)
                .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.borderWidth))
    }
}

/// A plain text button under the main one, e.g. "Skip for now".
struct SecondaryTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(Theme.Fonts.rowTitle)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget)
    }
}

extension View {
    func onboardingField() -> some View { modifier(OnboardingFieldStyle()) }

    /// Dims and turns off a button while a call runs or its input isn't ready.
    func onboardingEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.4)
    }
}
