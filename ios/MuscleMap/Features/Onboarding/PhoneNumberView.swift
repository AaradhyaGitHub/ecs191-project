import SwiftUI
import Networking
import OnboardingCore

/// Step 2a: the phone number, with a fixed "+1" (US only for now, Q-4).
struct PhoneNumberView: View {
    @Bindable var flow: SignInFlow
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingPage(title: "Your phone number", message: "We'll text you a 6-digit code.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("+1")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .onboardingField()
                    TextField("Phone number", text: $flow.phoneText,
                              prompt: Text("(530) 555-0000").foregroundStyle(Theme.Colors.textSecondary))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isFocused)
                        .onboardingField()
                }
                if let errorText = flow.errorText {
                    NoticeLine(text: errorText)
                }
            }
        } buttons: {
            PrimaryButton(title: "Send code") {
                Task { await flow.sendCode() }
            }
            .onboardingEnabled(!flow.isBusy && !flow.phoneText.isEmpty)
        }
        .onAppear { isFocused = true }
    }
}

#if DEBUG
#Preview("Phone number") {
    let flow = SignInFlow(api: PreviewData.onboardingAPI())
    flow.phoneText = PhoneNumber.display(APIClient.testPhoneNumber)
    return PhoneNumberView(flow: flow)
        .preferredColorScheme(.dark)
}
#endif
