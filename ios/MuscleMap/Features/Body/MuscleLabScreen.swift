import SwiftUI
import BodyCore

/// The MuscleLab page. The header works like the Fitness app's Summary: the date as the title,
/// a calendar button, and a swipeable week strip. Below it, Stats or Lab for the picked day.
struct MuscleLabScreen: View {
    @State private var model = MuscleLabModel()

    private let theme = BodyTheme.standard

    var body: some View {
        // NavigationStack gives us the iOS navigation bar (title + toolbar buttons).
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(model: model)
                    .padding(.top, 4)

                UnderlineTabs(options: MuscleLabModel.Mode.allCases, selection: $model.mode,
                              animation: theme.modeSwitchAnimation,
                              label: \.title, icon: { $0.icon })
                    .padding(.top, 4)

                GeometryReader { geometry in
                    ScrollView {
                        content(viewportHeight: geometry.size.height)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(model.initialScrollAnchor)
                }
            }
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { toolbar }
            .sheet(isPresented: $model.showingCalendar) {
                CalendarSheet(model: model)
                    .environment(\.bodyTheme, theme)
            }
        }
        .environment(\.bodyTheme, theme)
        .tint(theme.accent)
        // This page is designed dark-only, like the rest of the team's app.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(viewportHeight: CGFloat) -> some View {
        let analysis = model.selectedAnalysis
        Group {
            switch model.mode {
            case .stats:
                if let analysis {
                    StatsView(analysis: analysis)
                } else {
                    RestDayStatsView(model: model)
                }
            case .lab:
                LabView(model: model, analysis: analysis, viewportHeight: viewportHeight - 32)
            }
        }
        // A new id per day + mode rebuilds the content, so it cross-fades and the rings refill.
        .id("\(model.selectedDate.timeIntervalSince1970)-\(model.mode)")
        .transition(.opacity)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.title)
                .font(theme.navTitleFont)
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
                .animation(theme.modeSwitchAnimation, value: model.title)
        }
        if model.selectedDate != model.today {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    withAnimation(theme.modeSwitchAnimation) { model.select(model.today) }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.showingCalendar = true
            } label: {
                // Filled orange square with a dark icon, as in the design handoff.
                Image(systemName: "calendar")
                    .font(theme.calendarIconFont)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: theme.calendarButtonSize, height: theme.calendarButtonSize)
                    .background(RoundedRectangle(cornerRadius: theme.calendarButtonRadius).fill(theme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar")
        }
    }
}

#Preview {
    MuscleLabScreen()
}
