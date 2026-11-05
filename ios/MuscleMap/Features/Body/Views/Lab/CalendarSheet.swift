import SwiftUI
import BodyCore

/// Full-month calendar, like the Fitness app's: scroll through months, every day shows its ring,
/// tap a day to jump to it. The title follows the month you're looking at.
struct CalendarSheet: View {
    let model: MuscleLabModel

    @Environment(\.bodyTheme) private var theme
    /// `dismiss` closes this sheet (like calling an `onClose` prop the parent passed in).
    @Environment(\.dismiss) private var dismiss
    /// The month currently at the top of the scroll view.
    @State private var visibleMonth: Date?

    private var calendar: Calendar { model.calendar }

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            Rectangle().fill(theme.divider).frame(height: 0.5)

            ScrollView {
                LazyVStack(spacing: 28) {
                    ForEach(months, id: \.self) { month in
                        monthSection(month).id(month)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 16)
            }
            // Keeps `visibleMonth` in sync with whichever month is at the top while scrolling.
            .scrollPosition(id: $visibleMonth, anchor: .top)
            .onAppear { visibleMonth = monthStart(model.selectedDate) }
        }
        .background(theme.panelBackground)
    }

    private var header: some View {
        ZStack {
            Text((visibleMonth ?? model.selectedDate).formatted(.dateTime.month(.wide).year()))
                .font(theme.navTitleFont)
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(theme.accent)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(model.days(inWeekStarting: model.startOfWeek(model.today)), id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(theme.weekdayFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: Months

    /// First day of each month from the strip's earliest week up to this month.
    private var months: [Date] {
        let first = monthStart(model.weeks.first ?? model.today)
        let last = monthStart(model.today)
        var result: [Date] = []
        var month = first
        while month <= last {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthSection(_ month: Date) -> some View {
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        // Empty cells (nil) before day 1 so it lands under the right weekday, then pad the last row.
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading) + (1...max(dayCount, 1)).map { $0 }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }

        return VStack(alignment: .leading, spacing: 14) {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .font(theme.monthTitleFont)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 16)

            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let number = rows[rowIndex][column],
                           let day = calendar.date(byAdding: .day, value: number - 1, to: month) {
                            dayCell(day, number: number)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func dayCell(_ day: Date, number: Int) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: model.today)
        let isSelected = calendar.isDate(day, inSameDayAs: model.selectedDate)
        let future = model.isFuture(day)

        return Button {
            model.select(day)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Text("\(number)")
                    .font(theme.dayNumberFont)
                    .foregroundStyle(isToday ? theme.onAccent : isSelected ? theme.accent : theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background { if isToday { Circle().fill(theme.accent) } }
                DayRing(analysis: model.analysis(on: day), size: 42, dimmed: future)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(model.analysis(on: day).map { $0.session.title } ?? "No workout")
    }
}
