import SwiftUI
import BodyCore

/// Lab mode: the anatomy figure colored by the day's work, plus what to do with it
/// (split, next session, recovery, progression, rest).
struct LabView: View {
    /// `@Bindable` lets us make two-way bindings (`$model.groupFilter`) into an @Observable object.
    @Bindable var model: MuscleLabModel
    let analysis: WorkoutAnalysis?
    /// Height of the visible scroll area, so the full-body figure can fill most of the screen.
    let viewportHeight: CGFloat

    @Environment(\.bodyTheme) private var theme

    /// Full body takes most of the screen; a single group only needs about half.
    private var figureHeight: CGFloat {
        model.groupFilter == nil ? max(380, viewportHeight - 150) : max(260, viewportHeight * 0.45)
    }

    /// Effective sets shown on the figure: the day's session, or the last 7 days on a rest day.
    private var figureSets: [MuscleID: Double] {
        analysis?.muscleSets ?? model.weeklyMuscleSets(endingOn: model.selectedDate)
    }

    var body: some View {
        VStack(spacing: 14) {
            groupPicker
            figure
                .overlay(alignment: .top) {
                    if analysis == nil {
                        Text("Last 7 days")
                            .font(theme.chipFont)
                            .foregroundStyle(theme.accentSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(theme.accent.opacity(0.15)))
                    }
                }
            figureControls
            if let analysis {
                if let muscle = model.selectedMuscle {
                    MuscleDetailCard(muscle: muscle, analysis: analysis) { model.selectMuscle(nil) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                SplitCard(analysis: analysis, highlighted: model.highlightedPart) { part in
                    withAnimation(theme.focusAnimation) { model.toggleHighlight(part) }
                }
                NextSessionCard(analysis: analysis, calendar: model.calendar, isSessionDay: true)
                RecoveryCard(items: analysis.recovery, now: model.referenceTime(for: model.selectedDate))
                WeeklySetsCard(sets: model.weeklyPartSets(endingOn: model.selectedDate))
                ProgressionCard(analysis: analysis)
                RestCard(analysis: analysis)
            } else {
                RestDayCard(date: model.selectedDate, lastWorkout: model.lastAnalysis(before: model.selectedDate),
                            calendar: model.calendar)
                WeeklySetsCard(sets: model.weeklyPartSets(endingOn: model.selectedDate))
                let recovery = model.recovery(asOf: model.selectedDate)
                if !recovery.isEmpty {
                    RecoveryCard(items: recovery, now: model.referenceTime(for: model.selectedDate))
                }
                if let last = model.lastAnalysis(before: model.selectedDate),
                   last.nextSameSessionDate >= model.selectedDate {
                    NextSessionCard(analysis: last, calendar: model.calendar, isSessionDay: false)
                }
            }
        }
        .animation(theme.selectionAnimation, value: model.selectedMuscle)
        .onChange(of: model.groupFilter) { _, group in
            // A hidden muscle can't stay selected.
            if let group, let muscle = model.selectedMuscle, muscle.group != group {
                model.selectMuscle(nil)
            }
        }
    }

    // MARK: Controls

    private var groupPicker: some View {
        let trained = Set(figureSets.filter { $0.value > 0 }.keys.map(\.group))
        return PillPicker(options: [nil] + MuscleGroup.allCases.map(Optional.some),
                          selection: $model.groupFilter, compact: true, animation: theme.focusAnimation,
                          label: { $0?.displayName ?? "Full" },
                          badge: { group in group.map { trained.contains($0) } ?? false })
    }

    private var figureControls: some View {
        HStack(spacing: 10) {
            controlChip(model.bodyType.displayName,
                        icon: model.bodyType == .male ? "figure.stand" : "figure.stand.dress") {
                withAnimation(theme.viewSwitchAnimation) {
                    model.bodyType = model.bodyType == .male ? .female : .male
                }
            }
            .accessibilityLabel("Figure: \(model.bodyType.displayName). Double-tap to switch.")

            Spacer()
            legend
            Spacer()

            controlChip(model.facing == .front ? "Back" : "Front", icon: "arrow.triangle.2.circlepath") {
                withAnimation(theme.viewSwitchAnimation) {
                    model.facing = model.facing == .front ? .back : .front
                }
            }
            .accessibilityLabel("Show \(model.facing == .front ? "back" : "front")")
        }
    }

    private func controlChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(theme.chipFont)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.chipBackground))
                .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
        }
        .buttonStyle(.plain)
    }

    /// "fewer sets → more sets" color key.
    private var legend: some View {
        let top = figureSets.values.max() ?? 0
        return HStack(spacing: 6) {
            Text("0").foregroundStyle(theme.textSecondary)
            Capsule()
                .fill(LinearGradient(colors: [0.05, 0.5, 1].map { theme.colorScale.color(at: $0) },
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 54, height: 6)
            Text(LabFormat.setsLabel(top)).foregroundStyle(theme.textSecondary)
        }
        .font(theme.smallFont)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color key: brighter means more sets, up to \(LabFormat.sets(top)) sets")
    }

    // MARK: Figure

    private var figure: some View {
        BodyFigureView(
            values: figureValues,
            pulsing: analysis?.laggingMuscle.map { [$0] } ?? [],
            selected: model.selectedMuscle,
            side: model.facing,
            highlighted: Set(model.highlightedPart?.muscles ?? []),
            labelText: labelText,
            bodyType: model.bodyType,
            groupFilter: model.groupFilter,
            onTap: { muscle in model.selectMuscle(muscle) },
            onTapBackground: { model.selectMuscle(nil); model.highlightedPart = nil })
        // A new id per side makes SwiftUI treat front and back as different views,
        // so switching cross-fades between them instead of swapping instantly.
        .id("\(model.bodyType)-\(model.facing)")
        .transition(.opacity)
        .frame(height: figureHeight)
        .background(
            RadialGradient(colors: [theme.figureBackdrop, .clear], center: .center,
                           startRadius: 0, endRadius: figureHeight * 0.55)
        )
    }

    /// 0–1 per muscle, relative to the most-trained muscle.
    private var figureValues: [MuscleID: Double] {
        let sets = figureSets
        let top = max(sets.values.max() ?? 1, 1)
        return sets.mapValues { $0 / top }
    }

    /// Only muscles that did work get a label, showing their effective sets.
    private var labelText: [MuscleID: String] {
        figureSets.filter { $0.value >= 0.5 }.mapValues { LabFormat.setsLabel($0) }
    }
}

// MARK: - Insight cards

/// What a tapped muscle got today and from which exercises.
private struct MuscleDetailCard: View {
    let muscle: MuscleID
    let analysis: WorkoutAnalysis
    let onClose: () -> Void

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        let sets = analysis.muscleSets[muscle] ?? 0
        let sources = analysis.contributions(to: muscle)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(muscle.displayName)
                        .font(theme.cardTitleFont)
                        .foregroundStyle(theme.textPrimary)
                    Text(muscle.bodyPart.displayName)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(LabFormat.sets(sets))
                    .font(theme.statValueFont)
                    .foregroundStyle(theme.accentSoft)
                Text("sets")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(theme.closeIconFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if sources.isEmpty {
                Text("Not trained on this day.")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(sources, id: \.exercise.id) { source in
                    HStack {
                        Text(source.exercise.name)
                        Spacer()
                        Text(LabFormat.setsLabel(source.sets))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                }
            }
            if muscle == analysis.laggingMuscle {
                Label("Fewest sets of today's \(analysis.session.group.displayName.lowercased()) muscles",
                      systemImage: "waveform.path.ecg")
                    .font(theme.captionFont.weight(.semibold))
                    .foregroundStyle(theme.pulseColor)
            }
        }
        .labCard(border: theme.accent.opacity(0.5))
    }
}

/// Chest 51% / Shoulders 33% / Triceps 16%. Tap a row to outline those muscles.
private struct SplitCard: View {
    let analysis: WorkoutAnalysis
    let highlighted: BodyPart?
    let onTap: (BodyPart) -> Void

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's split")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("tap to highlight")
                    .font(theme.smallFont)
                    .foregroundStyle(theme.textTertiary)
            }
            HStack(spacing: 16) {
                SplitRing(segments: analysis.split.map {
                    RingSegment(id: $0.part.rawValue, color: theme.color(for: $0.part), share: $0.share)
                }, lineWidth: 14)
                .frame(width: 92, height: 92)

                VStack(spacing: 4) {
                    ForEach(analysis.split) { item in
                        row(item)
                    }
                }
            }
        }
        .labCard()
    }

    private func row(_ item: WorkoutAnalysis.PartShare) -> some View {
        let isOn = highlighted == item.part
        return Button { onTap(item.part) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.color(for: item.part))
                    .frame(width: 10, height: 10)
                Text(item.part.displayName)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(LabFormat.setsLabel(analysis.partSets[item.part] ?? 0))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Text(LabFormat.percent(item.share))
                    .font(theme.rowValueFont)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(theme.bodyFont)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? theme.accent.opacity(0.18) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.part.displayName), \(LabFormat.percent(item.share)) of volume")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "Next push: Fri, Nov 6", what to start with, and the days in between.
private struct NextSessionCard: View {
    let analysis: WorkoutAnalysis
    let calendar: Calendar
    /// True when shown on the session's own day (then the lagging muscle is pulsing on the figure).
    let isSessionDay: Bool

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        let session = analysis.session
        let when = isSessionDay ? "today" : "on \(session.start.formatted(.dateTime.weekday(.abbreviated)))"
        let next = analysis.nextSameSessionDate
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Next \(session.group.displayName)", icon: "arrow.right", color: theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(LabFormat.shortDay(next))
                    .font(theme.statValueFont)
                    .foregroundStyle(theme.textPrimary)
                Text("Everything you trained is recovered after \(LabFormat.time(next)).")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }

            if let lagging = analysis.laggingMuscle {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start with \(lagging.suggestedExercise)")
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(lagging.displayName) got the fewest sets \(when) (\(LabFormat.sets(analysis.muscleSets[lagging] ?? 0)))."
                             + (isSessionDay ? " It's pulsing on the figure." : ""))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            Rectangle().fill(theme.divider).frame(height: 0.5)

            VStack(spacing: 8) {
                ForEach(analysis.plan(calendar: calendar), id: \.day) { item in
                    HStack {
                        Text(calendar.isDateInToday(item.day) ? "Today" : item.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(theme.captionFont.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 48, alignment: .leading)
                        Text(item.group.displayName)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(item.group == session.group ? theme.accent : theme.textPrimary)
                        Spacer()
                        Text(planNote(item.group))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .labCard(tint: theme.accentTint, border: theme.accent.opacity(0.55))
    }

    private func planNote(_ group: MuscleGroup) -> String {
        switch group {
        case analysis.session.group: "recovered"
        case .pull: "back & biceps are fresh"
        case .legs: "legs are fresh"
        case .core, .push: "fresh"
        }
    }
}

/// How long each part needs, and how far along it is right now.
private struct RecoveryCard: View {
    let items: [WorkoutAnalysis.Recovery]
    let now: Date

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recovery")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("rest before training again")
                    .font(theme.smallFont)
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(items) { item in
                let progress = item.progress(now: now)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.part.displayName)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(Int(item.hours)) h")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(progress >= 1 ? "Ready" : "Ready \(LabFormat.shortDay(item.readyAt))")
                            .font(theme.captionFont.weight(.semibold))
                            .foregroundStyle(progress >= 1 ? theme.accent : theme.textSecondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.ringTrack)
                            Capsule()
                                .fill(theme.color(for: item.part))
                                .frame(width: max(6, geometry.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(Int(progress * 100)) percent recovered")
            }
            Text("Rule of thumb: about 24 h + 3 h per hard set, up to 72 h for big muscles.")
                .font(theme.smallFont)
                .foregroundStyle(theme.textTertiary)
        }
        .labCard()
    }
}

/// Double progression: add weight once every top set hits the rep goal, otherwise chase reps.
private struct ProgressionCard: View {
    let analysis: WorkoutAnalysis

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Next time")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("weight × reps at your top weight")
                    .font(theme.smallFont)
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.bottom, 8)

            ForEach(analysis.progressions) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.exercise.shortName)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(LabFormat.load(item.topWeight)) × \(item.repsAtTop.map(String.init).joined(separator: ", "))")
                            .font(theme.smallFont.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    badge(item)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .labCard()
    }

    @ViewBuilder
    private func badge(_ item: WorkoutAnalysis.Progression) -> some View {
        if item.addWeight {
            Label("\(LabFormat.weight(item.nextWeight))", systemImage: "arrow.up")
                .font(theme.chipFont)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accent))
        } else {
            Text("Aim for \(item.exercise.repGoal) reps")
                .font(theme.chipFont)
                .foregroundStyle(theme.accentSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(theme.accentSoft.opacity(0.5), lineWidth: 1))
        }
    }
}

/// Average rest, where reps fell off, and how much time shorter isolation rests would save.
private struct RestCard: View {
    let analysis: WorkoutAnalysis

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        let saving = analysis.isolationRestSaving
        let dropOffs = analysis.repDropOffs
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rest")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if let average = analysis.session.averageRest {
                    Text(LabFormat.rest(average))
                        .font(theme.statValueFont)
                        .foregroundStyle(theme.accentDeep)
                    Text("avg")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            if analysis.session.averageRest == nil && dropOffs.isEmpty {
                Text("No rest times logged for this session.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
            if !dropOffs.isEmpty {
                tip(icon: "chart.line.downtrend.xyaxis",
                    title: "Rest \(LabFormat.restRange(WorkoutAnalysis.compoundRest)) on heavy presses",
                    detail: dropOffs.map { "\($0.exercise.shortName) fell \($0.from) → \($0.to) reps at \(LabFormat.weight($0.weight))" }
                        .joined(separator: ". ") + ".")
            }
            if saving.seconds >= 60 {
                tip(icon: "timer",
                    title: "\(LabFormat.rest(WorkoutAnalysis.isolationRest)) is enough on isolation lifts",
                    detail: "\(saving.sets) isolation sets at that rest would cut about \(LabFormat.duration(saving.seconds)) from the session.")
            }
        }
        .labCard()
    }

    private func tip(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(theme.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown on days with nothing logged.
struct RestDayCard: View {
    let date: Date
    var lastWorkout: WorkoutAnalysis? = nil
    let calendar: Calendar

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(theme.restIconFont)
                .foregroundStyle(theme.accentSoft)
                .frame(width: 48, height: 48)
                .background(Circle().fill(theme.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest day")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .labCard()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let last = lastWorkout else { return "Nothing logged on this day." }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.session.start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let when = days == 1 ? (calendar.isDateInToday(date) ? "yesterday" : "the day before") : "\(days) days earlier"
        return "Last workout: \(last.session.title), \(when)."
    }
}

/// Effective sets per body part over the last 7 days, against the common 10–20 sets/week target.
struct WeeklySetsCard: View {
    let sets: [BodyPart: Double]

    @Environment(\.bodyTheme) private var theme

    private static let target: ClosedRange<Double> = 10...20
    private static let scaleMax: Double = 25

    var body: some View {
        let rows = sets.filter { $0.value >= 1 }.sorted { $0.value > $1.value }
        let missed = BodyPart.allCases.filter { (sets[$0] ?? 0) < 1 }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 7 days")
                    .font(theme.cardTitleFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("target 10–20 sets / muscle")
                    .font(theme.smallFont)
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(rows, id: \.key) { part, value in
                HStack(spacing: 10) {
                    Text(part.displayName)
                        .font(theme.captionFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 84, alignment: .leading)
                    bar(value, color: theme.color(for: part))
                    Text(LabFormat.sets(value))
                        .font(theme.captionFont.weight(.bold).monospacedDigit())
                        .foregroundStyle(Self.target.contains(value) ? theme.textPrimary
                                         : value < Self.target.lowerBound ? theme.textSecondary : theme.accent)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if !missed.isEmpty {
                Text("Not trained: \(missed.map(\.displayName).joined(separator: ", "))")
                    .font(theme.smallFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .labCard()
    }

    /// A bar with the 10–20 target zone shaded behind it.
    private func bar(_ value: Double, color: Color) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ringTrack)
                Rectangle()
                    .fill(theme.accent.opacity(0.12))
                    .frame(width: width * (Self.target.upperBound - Self.target.lowerBound) / Self.scaleMax)
                    .offset(x: width * Self.target.lowerBound / Self.scaleMax)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, width * min(value, Self.scaleMax) / Self.scaleMax))
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}
