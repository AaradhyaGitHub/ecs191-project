import SwiftUI
import Models
import LiftCore

/// The bottom sheet for one set (client_architecture.llm.md, "Lift screens", 5): set number and
/// type, the hero load with "Same as last set", the plate loader (barbells), REPS (or seconds),
/// REST AFTER, EFFORT and "Log 6 × 155 lb".
struct SetEntrySheet: View {
    let request: SetSheetRequest
    let unit: WeightUnit
    let onUnitChange: (WeightUnit) -> Void
    let onSubmit: (SetDraft) -> Void

    @State private var draft: SetDraft
    @State private var plates: PlateLoad
    @Environment(\.dismiss) private var dismiss

    init(request: SetSheetRequest, unit: WeightUnit, onUnitChange: @escaping (WeightUnit) -> Void,
         onSubmit: @escaping (SetDraft) -> Void) {
        self.request = request
        self.unit = unit
        self.onUnitChange = onUnitChange
        self.onSubmit = onSubmit
        // Every value starts inside its limit (D-25); the steppers keep it there.
        let draft = request.draft.clamped()
        _draft = State(initialValue: draft)
        _plates = State(initialValue: Self.plates(for: draft.weight, unit: unit))
    }

    private var kind: EntryKind { entryKind(for: draft.loadType) }

    /// Plate taps set the weight to the bar's total. Other plate changes ("Same as last set",
    /// the unit switch) only redraw the bar and keep the exact weight.
    private var plateTaps: Binding<PlateLoad> {
        Binding(get: { plates }, set: { load in
            plates = load
            draft.weight = Weight(load.total, load.plateSet.unit)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                setTypePicker
                hero
                if kind == .plates {
                    PlateLoader(load: plateTaps)
                }
                if kind != .seconds {
                    StepperRow(title: "Reps", value: "\(draft.reps)",
                               onMinus: { draft.stepReps(by: -1) }, onPlus: { draft.stepReps(by: 1) })
                }
                if request.editing == nil {
                    StepperRow(title: "Rest after", value: clockText(seconds: draft.restAfterS),
                               onMinus: { draft.stepRestAfter(by: -1) },
                               onPlus: { draft.stepRestAfter(by: 1) })
                }
                effortPicker
            }
            .padding(Theme.Spacing.gutter)
        }
        // Log stays on screen below the scrolling content, however tall the sheet gets (#63).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: LocalizedStringKey(primaryTitle)) {
                onSubmit(draft.clamped())
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.sheet)
        }
        .background(Theme.Colors.sheet)
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.sheet)
        .onChange(of: unit) { _, newUnit in
            plates = Self.plates(for: draft.weight, unit: newUnit)
        }
    }

    private var primaryTitle: String {
        request.editing == nil ? logButtonTitle(for: draft, unit: unit) : "Save set"
    }

    // MARK: Header and set type

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(request.exercise.name)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(draft.setType == .warmup ? "Warm-up set" : "Set \(request.number)")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if kind != .seconds {
                Picker("Units", selection: Binding(get: { unit }, set: onUnitChange)) {
                    Text("lb").tag(WeightUnit.lb)
                    Text("kg").tag(WeightUnit.kg)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var setTypePicker: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(SetType.allCases, id: \.self) { type in
                Chip(title: Self.name(of: type), isSelected: draft.setType == type, fillsWidth: true) {
                    draft.setType = type
                }
            }
        }
    }

    static func name(of type: SetType) -> String {
        switch type {
        case .warmup: "Warm-up"
        case .working: "Working"
        case .dropset: "Drop set"
        case .failure: "Failure"
        }
    }

    // MARK: Hero load

    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch kind {
            case .plates, .perDumbbell, .weight:
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(weightNumberText(draft.weight, unit: unit))
                        .font(Theme.Fonts.hero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityLabel("Weight \(weightText(draft.weight, unit: unit))")
                    Text(kind == .perDumbbell ? "\(unit.rawValue) per dumbbell" : unit.rawValue)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if kind != .plates {
                        stepperButtons(minus: { draft.stepWeight(by: -1, unit: unit) },
                                       plus: { draft.stepWeight(by: 1, unit: unit) })
                    }
                }
                if kind == .plates {
                    Text(plates.breakdown)
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            case .bodyweight:
                HStack(alignment: .firstTextBaseline) {
                    Text(bodyweightText(addedLoad: draft.addedLoad, unit: unit))
                        .font(Theme.Fonts.hero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    stepperButtons(minus: { draft.stepAddedLoad(by: -1, unit: unit) },
                                   plus: { draft.stepAddedLoad(by: 1, unit: unit) })
                }
            case .seconds:
                HStack(alignment: .firstTextBaseline) {
                    Text("\(draft.durationS) s")
                        .font(Theme.Fonts.hero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    stepperButtons(minus: { draft.stepDuration(by: -1) },
                                   plus: { draft.stepDuration(by: 1) })
                }
            }
            if let last = request.lastSet {
                Button("Same as last set") {
                    draft.apply(last)
                    plates = Self.plates(for: draft.weight, unit: unit)
                }
                .font(Theme.Fonts.secondary.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Size.minTouchTarget)
            }
        }
    }

    /// The plates for a weight: the nearest load the plates can make, not above it.
    private static func plates(for weight: Weight, unit: WeightUnit) -> PlateLoad {
        PlateLoad.nearestLoad(to: weight.value(in: unit), with: .standard(for: unit))
    }

    private func stepperButtons(minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            RoundButton(systemImage: "minus", label: "Less", action: minus)
            RoundButton(systemImage: "plus", label: "More", action: plus)
        }
    }

    // MARK: Effort

    private var effortPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Effort")
            HStack(spacing: Theme.Spacing.s) {
                ForEach(SetSteps.effortRange, id: \.self) { pct in
                    Button { draft.effortPct = pct } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            // Traffic-light colors; the chip's text color when selected, so
                            // the failure flame stays visible on the accent (#63).
                            EffortBattery(effortPct: pct,
                                          tint: draft.effortPct == pct ? Theme.Colors.onAccent : nil)
                            Text("\(pct)%")
                                .font(Theme.Fonts.secondary.monospacedDigit())
                        }
                        .foregroundStyle(draft.effortPct == pct ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget + Theme.Spacing.m)
                        .background(draft.effortPct == pct ? Theme.Colors.accent : Theme.Colors.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.effortPct == pct ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Parts

/// REPS and REST AFTER: a caps label, the value, and − / + buttons.
private struct StepperRow: View {
    let title: String
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: title)
                Text(value)
                    .font(Theme.Fonts.cardTitle.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
            RoundButton(systemImage: "minus", label: "Less \(title.lowercased())", action: onMinus)
            RoundButton(systemImage: "plus", label: "More \(title.lowercased())", action: onPlus)
        }
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.smallButton))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A selectable chip: set types here, exercise filters in the set log.
/// `fillsWidth` chips share a row equally with smaller side padding, so four set types fit on
/// one line on a 375 pt phone without "Warm-…" (#63).
struct Chip: View {
    let title: String
    let isSelected: Bool
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.secondary.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .padding(.horizontal, fillsWidth ? Theme.Spacing.s : Theme.Spacing.m)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: Theme.Size.minTouchTarget)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Barbell") {
    SetEntrySheet(
        request: SetSheetRequest(
            blockID: "b", exercise: PreviewData.benchPress,
            draft: SetDraft(exerciseId: PreviewData.benchPress.id, loadType: .barbell, reps: 6,
                            weight: Weight(155, .lb)),
            editing: nil, lastSet: PreviewData.myExercises[2].lastSet, number: "3"),
        unit: .lb, onUnitChange: { _ in }, onSubmit: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Barbell, 375 pt phone") {
    SetEntrySheet(
        request: SetSheetRequest(
            blockID: "b", exercise: PreviewData.benchPress,
            draft: SetDraft(exerciseId: PreviewData.benchPress.id, loadType: .barbell, setType: .warmup,
                            reps: 6, weight: Weight(155, .lb)),
            editing: nil, lastSet: PreviewData.myExercises[2].lastSet, number: "3"),
        unit: .lb, onUnitChange: { _ in }, onSubmit: { _ in })
        .frame(width: 375)
        .preferredColorScheme(.dark)
}

#Preview("Bodyweight") {
    SetEntrySheet(
        request: SetSheetRequest(
            blockID: "b", exercise: PreviewData.pushUp,
            draft: SetDraft(exerciseId: PreviewData.pushUp.id, loadType: .bodyweight, reps: 20,
                            addedLoad: Weight(10, .lb)),
            editing: nil, lastSet: nil, number: "1"),
        unit: .lb, onUnitChange: { _ in }, onSubmit: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Timed") {
    SetEntrySheet(
        request: SetSheetRequest(
            blockID: "b", exercise: PreviewData.plank,
            draft: SetDraft(exerciseId: PreviewData.plank.id, loadType: .timed, durationS: 45),
            editing: nil, lastSet: nil, number: "1"),
        unit: .lb, onUnitChange: { _ in }, onSubmit: { _ in })
        .preferredColorScheme(.dark)
}
#endif
