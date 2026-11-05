import SwiftUI
import BodyCore

/// Stats mode on a day with no workout: what you did last, and the 7 days leading up to it.
struct RestDayStatsView: View {
    let model: MuscleLabModel

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        let last = model.lastAnalysis(before: model.selectedDate)
        VStack(spacing: 16) {
            RestDayCard(date: model.selectedDate, lastWorkout: last, calendar: model.calendar)
            if let last {
                lastWorkoutCard(last)
            }
            weekCard
        }
    }

    // MARK: Last workout

    private func lastWorkoutCard(_ analysis: WorkoutAnalysis) -> some View {
        let session = analysis.session
        return Button {
            withAnimation(theme.modeSwitchAnimation) { model.select(session.start) }
        } label: {
            HStack(spacing: 14) {
                DayRing(analysis: analysis, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST WORKOUT")
                        .font(theme.smallFont.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(theme.accent)
                    Text("\(session.title) · \(LabFormat.shortDay(session.start))")
                        .font(theme.rowFont)
                        .foregroundStyle(theme.textPrimary)
                    Text("\(session.setCount) sets · \(LabFormat.weight(session.volume))")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.textTertiary)
            }
            .labCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows that day")
    }

    // MARK: 7 days

    private var weekCard: some View {
        let week = model.week(endingOn: model.selectedDate)
        let end = model.calendar.startOfDay(for: model.selectedDate)
        let days = (0..<7).reversed().compactMap { model.calendar.date(byAdding: .day, value: -$0, to: end) }
        let peak = max(week.map(\.session.volume).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Last 7 days")
                .font(theme.cardTitleFont)
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 0) {
                summary("Workouts", "\(week.count)", theme.accent)
                summary("Sets", "\(week.reduce(0) { $0 + $1.session.setCount })", theme.accentSoft)
                summary("Volume", LabFormat.number(week.reduce(0) { $0 + $1.session.volume }), theme.textPrimary)
            }

            // One bar per day, colored by that day's main body part.
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let analysis = model.analysis(on: day)
                    VStack(spacing: 6) {
                        Text(analysis.map { String($0.session.title.prefix(4)) } ?? "")
                            .font(theme.smallFont.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(analysis.flatMap { $0.split.first }.map { theme.color(for: $0.part) } ?? theme.ringTrack)
                            .frame(height: max(6, 90 * (analysis?.session.volume ?? 0) / peak))
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(theme.weekdayFont)
                            .foregroundStyle(model.calendar.isDate(day, inSameDayAs: model.selectedDate)
                                             ? theme.accent : theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(analysis.map { "\($0.session.title), \(LabFormat.weight($0.session.volume))" } ?? "Rest")
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .labCard()
    }

    private func summary(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(theme.statLabelFont)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(theme.statValueFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
