import SwiftUI
import BodyCore

/// The row of seven days under the title, like the Fitness app's Summary.
/// Swipe sideways for other weeks; tap a day to show it. Each day shows that day's split ring.
struct WeekStrip: View {
    let model: MuscleLabModel

    @Environment(\.bodyTheme) private var theme
    /// Which week page is showing.
    @State private var weekIndex = 0

    var body: some View {
        let weeks = model.weeks
        VStack(spacing: 6) {
            weekdayHeader

            // A page-style TabView is a horizontal pager (like a swiper carousel in React).
            TabView(selection: $weekIndex) {
                ForEach(weeks.indices, id: \.self) { index in
                    weekRow(weeks[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 50)
        }
        .padding(.horizontal, 8)
        .onAppear { weekIndex = index(of: model.selectedDate, in: weeks) }
        // Swiping to another week keeps the same weekday selected (never a future day).
        .onChange(of: weekIndex) { _, newIndex in
            guard weeks.indices.contains(newIndex) else { return }
            let weekday = model.calendar.component(.weekday, from: model.selectedDate)
            let days = model.days(inWeekStarting: weeks[newIndex])
            let sameWeekday = days.first { model.calendar.component(.weekday, from: $0) == weekday }
            if let day = sameWeekday {
                withAnimation(theme.modeSwitchAnimation) { model.select(min(day, model.today)) }
            }
        }
        // Picking a day from the calendar sheet jumps to its week.
        .onChange(of: model.selectedDate) { _, date in
            let target = index(of: date, in: weeks)
            if target != weekIndex { weekIndex = target }
        }
    }

    private func index(of date: Date, in weeks: [Date]) -> Int {
        weeks.firstIndex(of: model.startOfWeek(date)) ?? max(weeks.count - 1, 0)
    }

    /// M T W T F S S, with the selected day's letter in a filled circle (orange for today).
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekIndexDays, id: \.self) { day in
                let isSelected = model.calendar.isDate(day, inSameDayAs: model.selectedDate)
                let isToday = model.calendar.isDate(day, inSameDayAs: model.today)
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(theme.weekdayFont)
                    .foregroundStyle(isSelected ? (isToday ? theme.onAccent : .black)
                                     : isToday ? theme.accent : theme.textSecondary)
                    .frame(width: theme.weekdayCircleSize, height: theme.weekdayCircleSize)
                    .background {
                        if isSelected { Circle().fill(isToday ? theme.accent : theme.textPrimary) }
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var weekIndexDays: [Date] {
        let weeks = model.weeks
        let start = weeks.indices.contains(weekIndex) ? weeks[weekIndex] : model.startOfWeek(model.today)
        return model.days(inWeekStarting: start)
    }

    private func weekRow(_ start: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(model.days(inWeekStarting: start), id: \.self) { day in
                let future = model.isFuture(day)
                let analysis = model.analysis(on: day)
                Button {
                    withAnimation(theme.modeSwitchAnimation) { model.select(day) }
                } label: {
                    DayRing(analysis: analysis, size: 40, dimmed: future)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(future)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityValue(analysis.map { $0.session.title } ?? "No workout")
                .accessibilityAddTraits(model.calendar.isDate(day, inSameDayAs: model.selectedDate) ? .isSelected : [])
            }
        }
    }
}
