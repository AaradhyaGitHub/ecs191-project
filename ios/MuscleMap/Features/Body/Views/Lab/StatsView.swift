import SwiftUI
import BodyCore

/// Stats mode for a workout day, laid out as in the design handoff
/// (`design_handoff_workout_stats/`): summary gauge, training focus, highlights, exercises.
struct StatsView: View {
    let analysis: WorkoutAnalysis

    @Environment(\.bodyTheme) private var theme
    /// Drives the gauge arcs growing when the day appears.
    @State private var gaugeProgress = 0.0

    private var style: StatsStyle { theme.stats }

    var body: some View {
        VStack(spacing: 12) {
            SummaryGauge(analysis: analysis, progress: gaugeProgress)
            TrainingFocusCard(analysis: analysis)
            sectionHeader("Highlights")
            HStack(alignment: .top, spacing: 10) {
                if let ticker = analysis.heaviestTicker {
                    TickerTile(ticker: ticker, title: "Heaviest lift", icon: "dumbbell.fill",
                               tint: theme.accent, value: LabFormat.weight(ticker.value))
                }
                if let ticker = analysis.mostMovedTicker {
                    TickerTile(ticker: ticker, title: "Most moved", icon: "flame.fill",
                               tint: theme.accentSoft, value: LabFormat.weight(ticker.value))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            sectionHeader("Exercises")
            ExerciseListCard(analysis: analysis)
        }
        .onAppear {
            gaugeProgress = 0
            withAnimation(theme.ringFillAnimation.delay(0.1)) { gaugeProgress = 1 }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        SectionTitle(text: text)
            .padding(.top, 10)
            .padding(.leading, 4)
    }
}

// MARK: - 1. Summary gauge

/// A half ring (volume split by body part) over the total, then a 5-stat strip.
private struct SummaryGauge: View {
    let analysis: WorkoutAnalysis
    let progress: Double

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }
    private var session: WorkoutSession { analysis.session }

    /// The full circle is 220pt with a 96pt radius; only its top half (118pt) is shown.
    private let boxSize: CGFloat = 220
    private let radius: CGFloat = 96
    private let visibleHeight: CGFloat = 118

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                arcs
                    .frame(width: boxSize, height: visibleHeight, alignment: .top)
                    .clipped()
                VStack(spacing: 1) {
                    Text(LabFormat.number(session.volume))
                        .font(style.gaugeValueFont)
                        .tracking(-1)
                        .foregroundStyle(theme.textPrimary)
                    HStack(spacing: 0) {
                        Text("LB · ").foregroundStyle(theme.textSecondary)
                        Text(session.title.uppercased()).foregroundStyle(theme.accent)
                    }
                    .font(style.gaugeUnitFont)
                    .tracking(1.4)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.title), \(LabFormat.number(session.volume)) pounds. "
                                + analysis.split.map { "\($0.part.displayName) \(LabFormat.percent($0.share))" }
                                    .joined(separator: ", "))

            statStrip
        }
        .padding(.top, 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(cardBackground)
    }

    /// One butt-capped arc per body part, sharing 180° in proportion to volume, with ~2pt gaps.
    private var arcs: some View {
        let gap = 2 / (2 * .pi * radius)   // 2pt as a fraction of the full circle
        let split = analysis.split
        return ZStack {
            ForEach(Array(split.enumerated()), id: \.element.id) { index, item in
                let start = split[..<index].reduce(0) { $0 + $1.share } * 0.5 * progress
                let end = start + item.share * 0.5 * progress
                Circle()
                    .trim(from: start + (index > 0 ? gap / 2 : 0),
                          to: max(start, end - (index < split.count - 1 ? gap / 2 : 0)))
                    .stroke(theme.color(for: item.part), style: StrokeStyle(lineWidth: style.gaugeLineWidth, lineCap: .butt))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        // Trim starts at 3 o'clock and runs clockwise; turning it 180° makes it run left → right over the top.
        .rotationEffect(.degrees(180))
        .frame(width: boxSize, height: boxSize)
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            stat("\(session.setCount)", "sets", theme.accent)
            stat("\(session.reps)", "reps", theme.accentSoft)
            stat("\(session.exercises.count)", "exercises", theme.textPrimary)
            stat(session.duration.map(LabFormat.clock(hoursMinutes:)) ?? "—", "duration", theme.textPrimary)
            stat(session.averageRest.map(LabFormat.clock(minutesSeconds:)) ?? "—", "avg rest", theme.accentDeep)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: style.insetCornerRadius, style: .continuous).fill(style.inset))
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(style.stripValueFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(style.stripLabelFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
            .fill(theme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth)
            )
    }
}

// MARK: - 2. Training focus

/// Volume of each working set as a thin line, with every set's dot colored by its rep zone.
private struct TrainingFocusCard: View {
    let analysis: WorkoutAnalysis

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }

    private let chartHeight: CGFloat = 90
    /// Keeps the first and last dots fully inside the card.
    private var inset: CGFloat { style.flowDotSize / 2 }

    var body: some View {
        let flow = analysis.workingFlow
        let counts = analysis.zoneCounts()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training focus")
                    .font(style.focusTitleFont)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if let headline = analysis.headlineZone {
                    HStack(spacing: 4) {
                        Text(headline.zone.title).foregroundStyle(theme.textPrimary)
                        Text(LabFormat.percent(headline.share)).foregroundStyle(style.hypertrophy)
                    }
                    .font(style.focusHeadlineFont)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                chart(flow)
                    .frame(height: chartHeight)
                segmentLabels(flow)
                    .frame(height: 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume of each working set, colored by rep zone")

            HStack(spacing: 14) {
                ForEach(RepZone.allCases, id: \.self) { zone in
                    HStack(spacing: 5) {
                        Circle().fill(style.color(for: zone)).frame(width: 7, height: 7)
                        Text(zone.title).foregroundStyle(theme.textSecondary)
                        Text("\(counts[zone, default: 0])").bold().foregroundStyle(theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .font(style.legendFont)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(theme.cardBorder).frame(height: 1) }
        }
        .labCard()
    }

    private func xPosition(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return inset + (width - 2 * inset) * CGFloat(index) / CGFloat(count - 1)
    }

    private func chart(_ flow: [(exercise: LabExercise, set: WorkoutSet)]) -> some View {
        let peak = max(flow.map(\.set.volume).max() ?? 1, 1)
        return Canvas { context, size in
            let points = flow.indices.map { index in
                CGPoint(x: xPosition(index, count: flow.count, width: size.width),
                        y: size.height - CGFloat(flow[index].set.volume / peak) * size.height * 0.88 - inset)
            }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(style.flowLine),
                           style: StrokeStyle(lineWidth: style.flowLineWidth, lineCap: .round, lineJoin: .round))
            let d = style.flowDotSize
            for (point, item) in zip(points, flow) {
                let dot = Path(ellipseIn: CGRect(x: point.x - d / 2, y: point.y - d / 2, width: d, height: d))
                context.fill(dot, with: .color(style.color(for: RepZone(reps: item.set.reps))))
            }
        }
    }

    /// One label per exercise, starting at its first working set, as wide as its sets.
    private func segmentLabels(_ flow: [(exercise: LabExercise, set: WorkoutSet)]) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let segments = analysis.session.exercises.compactMap { exercise -> (LabExercise, Int, Int)? in
                guard let first = flow.firstIndex(where: { $0.exercise.id == exercise.id }) else { return nil }
                return (exercise, first, flow.filter { $0.exercise.id == exercise.id }.count)
            }
            ZStack(alignment: .topLeading) {
                ForEach(segments, id: \.0.id) { exercise, first, count in
                    let x = xPosition(first, count: flow.count, width: width)
                    let segmentWidth = width * CGFloat(count) / CGFloat(max(flow.count, 1))
                    if segmentWidth >= 24 {
                        Text(exercise.info.chartName)
                            .font(style.segmentLabelFont)
                            .foregroundStyle(style.segmentLabelColor)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.leading, 3)
                            .frame(width: segmentWidth, height: 12, alignment: .leading)
                            .clipped()
                            .overlay(alignment: .leading) {
                                Rectangle().fill(style.segmentDivider).frame(width: 1)
                            }
                            .offset(x: x)
                    }
                }
            }
        }
    }
}

// MARK: - 3. Highlights

/// Stock-ticker tile: today's number, green ▲ / red ▼ change since last time, and a sparkline.
private struct TickerTile: View {
    let ticker: WorkoutAnalysis.Ticker
    let title: String
    let icon: String
    let tint: Color
    let value: String

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }

    private var deltaColor: Color {
        guard let change = ticker.change else { return theme.textSecondary }
        return change > 0 ? style.up : change < 0 ? style.down : theme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(style.tileIconFont)
                Text(title).font(style.tileLabelFont)
            }
            .foregroundStyle(tint)

            Text(value)
                .font(style.tileValueFont)
                .tracking(-0.8)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            delta

            if ticker.series.count >= 2 {
                Sparkline(values: ticker.series, color: deltaColor, lineWidth: style.sparklineWidth)
                    .frame(height: 40)
            } else {
                Spacer(minLength: 40)
            }

            Text(ticker.series.count >= 2 ? "\(ticker.exercise.shortName) · last \(ticker.series.count) sessions"
                                           : "\(ticker.exercise.shortName) · no history yet")
                .font(style.tileFooterFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: style.tileCornerRadius, style: .continuous)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: style.tileCornerRadius, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth)
                )
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var delta: some View {
        if let change = ticker.change {
            HStack(spacing: 4) {
                if change != 0 {
                    Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(style.deltaGlyphFont)
                }
                Text(deltaText(change))
            }
            .font(style.deltaFont)
            .foregroundStyle(deltaColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("First session")
                .font(style.deltaFont)
                .foregroundStyle(theme.textSecondary)
        }
    }

    /// "+10 lb (6.9%)", "−220 lb (4.2%)", or "±0".
    private func deltaText(_ change: Double) -> String {
        guard change != 0 else { return "±0" }
        let sign = change > 0 ? "+" : "−"
        let percent = abs(ticker.percentChange ?? 0) * 100
        return "\(sign)\(LabFormat.weight(abs(change))) (\(percent.formatted(.number.precision(.fractionLength(1))))%)"
    }
}

/// A small line chart with no axes and a dot on the last (today's) point.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let pad: CGFloat = 4
            let range = max(high - low, 1)
            let points = values.indices.map { index in
                CGPoint(x: pad + (size.width - 2 * pad) * CGFloat(index) / CGFloat(values.count - 1),
                        y: size.height - pad - (size.height - 2 * pad) * CGFloat((values[index] - low) / range))
            }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }
}

// MARK: - 4. Exercises

/// Each row is a volume bar; tapping one opens its sets, 3 per page, swipeable, with page dots.
private struct ExerciseListCard: View {
    let analysis: WorkoutAnalysis

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }

    /// Only one row open at a time. The first exercise starts open.
    @State private var openID: String?
    @State private var didSetDefault = false
    /// Page shown for each exercise, kept while a row is closed and reopened.
    @State private var pages: [String: Int] = [:]

    var body: some View {
        let exercises = analysis.session.exercises
        let peak = max(exercises.map(\.volume).max() ?? 1, 1)

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(exercises.count) exercises")
                    .font(style.listHeaderFont)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("volume · tap to see sets")
                    .font(style.listHintFont)
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)

            ForEach(exercises) { exercise in
                ExerciseRow(exercise: exercise, share: exercise.volume / peak,
                            isPR: analysis.prSetIndex(in: exercise) != nil,
                            prSetIndex: analysis.prSetIndex(in: exercise),
                            isOpen: openID == exercise.id,
                            page: Binding(get: { pages[exercise.id] ?? 0 }, set: { pages[exercise.id] = $0 })) {
                    withAnimation(style.expandAnimation) {
                        openID = openID == exercise.id ? nil : exercise.id
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth)
                )
        )
        .onAppear {
            if !didSetDefault {
                openID = exercises.first?.id
                didSetDefault = true
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: LabExercise
    /// Volume ÷ the day's biggest exercise volume (bar width).
    let share: Double
    let isPR: Bool
    let prSetIndex: Int?
    let isOpen: Bool
    @Binding var page: Int
    let onToggle: () -> Void

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }

    private var barColor: Color { theme.color(for: exercise.part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: style.barHeight / 2)
                            .fill(barColor)
                            .frame(width: max(style.barHeight, geometry.size.width * share))
                    }
                    .frame(height: style.barHeight)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(exercise.name), \(exercise.sets.count) sets, \(LabFormat.weight(exercise.volume))\(isPR ? ", personal record" : "")")
            .accessibilityHint(isOpen ? "Hides the sets" : "Shows the sets")

            if isOpen {
                SetPager(exercise: exercise, prSetIndex: prSetIndex, color: barColor, page: $page)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: style.insetCornerRadius, style: .continuous)
                .fill(isOpen ? style.openRow : .clear)
        )
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(exercise.name)
                .font(style.rowNameFont)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isPR {
                PRBadge(font: style.prBadgeFont)
            }
            Text("\(exercise.sets.count)×")
                .font(style.rowCountFont)
                .foregroundStyle(theme.textSecondary)
            Text(LabFormat.number(exercise.volume))
                .font(style.rowVolumeFont)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 58, alignment: .trailing)
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(style.chevronFont)
                .foregroundStyle(style.chevronColor)
                .frame(width: 20)
        }
    }
}

/// The yellow "PR" tag.
private struct PRBadge: View {
    let font: Font

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        Text("PR")
            .font(font)
            .foregroundStyle(theme.stats.prBadgeText)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: theme.stats.badgeCornerRadius).fill(theme.stats.prBadge))
    }
}

/// An exercise's sets, 3 cards per page. Swipe sideways or tap a dot to change page.
private struct SetPager: View {
    let exercise: LabExercise
    let prSetIndex: Int?
    let color: Color
    @Binding var page: Int

    @Environment(\.bodyTheme) private var theme
    private var style: StatsStyle { theme.stats }
    /// The page the scroll view is resting on (nil while it's between pages).
    @State private var scrolledPage: Int?

    private var pageCount: Int { (exercise.sets.count + 2) / 3 }

    var body: some View {
        VStack(spacing: 10) {
            // A horizontal ScrollView with paging behavior snaps one full page at a time,
            // like a carousel. `scrollPosition` tracks (and can set) which page is showing.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        pageView(index)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledPage)
            .onAppear { scrolledPage = page }
            .onChange(of: scrolledPage) { _, newValue in
                if let newValue { page = newValue }
            }

            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        let isActive = index == page
                        Capsule()
                            .fill(isActive ? color : style.inactiveDot)
                            .frame(width: isActive ? 16 : 6, height: 6)
                            .contentShape(Rectangle().inset(by: -6))
                            .onTapGesture {
                                withAnimation(.smooth) { scrolledPage = index }
                            }
                            .accessibilityLabel("Page \(index + 1) of \(pageCount)")
                    }
                }
                .animation(style.dotAnimation, value: page)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pageView(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { slot in
                let setIndex = index * 3 + slot
                if setIndex < exercise.sets.count {
                    setCard(setIndex)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func setCard(_ index: Int) -> some View {
        let set = exercise.sets[index]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("SET \(index + 1)")
                    .font(style.setLabelFont)
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 2)
                if index == prSetIndex {
                    PRBadge(font: style.setPRBadgeFont)
                } else if set.kind == .warmup {
                    Text("WARM")
                        .font(style.warmFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(height: 14)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(LabFormat.load(set.weight))
                    .font(style.setWeightFont)
                    .foregroundStyle(theme.textPrimary)
                if !set.isBodyweight {
                    Text("lb")
                        .font(style.setUnitFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Text("× \(set.reps) reps")
                .font(style.setRepsFont)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: style.setCardCornerRadius, style: .continuous).fill(style.inset))
        .accessibilityElement(children: .combine)
    }
}
