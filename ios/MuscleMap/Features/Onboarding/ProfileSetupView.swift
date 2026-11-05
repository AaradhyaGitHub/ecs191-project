import SwiftUI
import Models
import OnboardingCore

/// Step 3: name and units, then the optional body weight, sex, birth year and experience.
/// Only units has a value from the start (lb); everything else can stay empty (spec 1, Q-1).
struct ProfileSetupView: View {
    let flow: OnboardingFlow
    @State private var draft: ProfileDraft
    @State private var birthYearText: String

    init(flow: OnboardingFlow, user: User) {
        self.flow = flow
        let draft = ProfileDraft(user: user)
        _draft = State(initialValue: draft)
        _birthYearText = State(initialValue: draft.birthYear.map(String.init) ?? "")
    }

    var body: some View {
        OnboardingPage(title: "Your profile", message: "Only units are needed. Skip anything else.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                section("Name") {
                    TextField("Name", text: $draft.displayName, prompt: prompt("Optional"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .onboardingField()
                }
                section("Units") {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach([WeightUnit.lb, .kg], id: \.self) { unit in
                            Chip(title: unit.rawValue, isSelected: draft.units == unit, fillsWidth: true) {
                                draft.setUnits(unit)
                            }
                        }
                    }
                }
                section("Body weight") {
                    HStack(spacing: Theme.Spacing.s) {
                        TextField("Body weight", text: $draft.bodyweightText, prompt: prompt("Optional"))
                            .keyboardType(.decimalPad)
                        Text(draft.units.rawValue)
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .onboardingField()
                }
                section("Sex") {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(Self.sexes) { choice in
                            Chip(title: choice.title, isSelected: draft.sex == choice.value) {
                                draft.sex = choice.value
                            }
                        }
                    }
                }
                section("Birth year") {
                    TextField("Birth year", text: $birthYearText, prompt: prompt("Optional"))
                        .keyboardType(.numberPad)
                        .onboardingField()
                        .onChange(of: birthYearText) { _, text in
                            let digits = String(text.filter(\.isNumber).prefix(4))
                            if digits != text { birthYearText = digits }
                            draft.birthYear = Int(digits)
                        }
                }
                section("Experience") {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(Experience.allCases, id: \.self) { level in
                            // Tapping the chosen level again clears it (it's optional).
                            Chip(title: Self.name(of: level), isSelected: draft.experience == level,
                                 fillsWidth: true) {
                                draft.experience = draft.experience == level ? nil : level
                            }
                        }
                    }
                }
                if let errorText = flow.errorText {
                    NoticeLine(text: errorText)
                }
            }
        } buttons: {
            PrimaryButton(title: "Continue") {
                Task { await flow.saveProfile(draft) }
            }
            .onboardingEnabled(!flow.isSaving)
        }
    }

    /// Q-7: Female / Male / Prefer not to say (stored as null).
    static let sexes = [
        SexChoice(title: "Female", value: "female"), SexChoice(title: "Male", value: "male"),
        SexChoice(title: "Prefer not to say", value: nil),
    ]

    struct SexChoice: Identifiable {
        let title: String
        let value: String?
        var id: String { title }
    }

    static func name(of level: Experience) -> String {
        switch level {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Theme.Colors.textSecondary)
    }

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            OnboardingLabel(text: label)
            content()
        }
    }
}

#if DEBUG
#Preview("Profile, new user") {
    ProfileSetupView(flow: OnboardingFlow(api: PreviewData.onboardingAPI()),
                     user: PreviewData.newUser)
        .preferredColorScheme(.dark)
}

#Preview("Profile, prefilled") {
    ProfileSetupView(flow: OnboardingFlow(api: PreviewData.onboardingAPI()), user: PreviewData.user)
        .preferredColorScheme(.dark)
}
#endif
