import SwiftUI
import Networking
import OnboardingCore

/// Step 2b: the 6-digit code, with Resend code (after 30 s) and Change number.
struct CodeView: View {
    @Bindable var flow: SignInFlow
    @FocusState private var isFocused: Bool

    private var sentTo: String {
        flow.sentTo.map(PhoneNumber.display) ?? ""
    }

    var body: some View {
        OnboardingPage(title: "Enter the code", message: "Sent to \(sentTo).") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                TextField("Code", text: $flow.codeText,
                          prompt: Text("123456").foregroundStyle(Theme.Colors.textSecondary))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .onboardingField()
                    .onChange(of: flow.codeText) { _, text in
                        let clean = VerificationCode.sanitized(text)
                        if clean != text { flow.codeText = clean }
                    }
                #if DEBUG
                if flow.sentTo == APIClient.testPhoneNumber {
                    Text("Test code: \(APIClient.testCode)")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                #endif
                if let errorText = flow.errorText {
                    NoticeLine(text: errorText)
                }
            }
        } buttons: {
            PrimaryButton(title: "Verify") {
                Task { await flow.verify() }
            }
            .onboardingEnabled(!flow.isBusy && VerificationCode.isValid(flow.codeText))
            HStack {
                // Re-reads the countdown every second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let left = flow.resendAvailableIn()
                    Button(left > 0 ? "Resend in \(Self.clock(left))" : "Resend code") {
                        Task { await flow.resend() }
                    }
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(left > 0 ? Theme.Colors.textSecondary : Theme.Colors.accent)
                    .monospacedDigit()
                    .disabled(left > 0 || flow.isBusy)
                }
                Spacer()
                Button("Change number") { flow.changeNumber() }
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .disabled(flow.isBusy)
            }
            .frame(minHeight: Theme.Size.minTouchTarget)
        }
        .onAppear { isFocused = true }
    }

    /// 24 → "0:24".
    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

#if DEBUG
#Preview("Code") {
    let flow = SignInFlow(api: PreviewData.onboardingAPI())
    flow.phoneText = "5305550000"
    return CodeView(flow: flow)
        .task { await flow.sendCode() }
        .preferredColorScheme(.dark)
}
#endif
