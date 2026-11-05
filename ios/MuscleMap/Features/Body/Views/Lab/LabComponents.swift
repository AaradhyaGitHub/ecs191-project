import SwiftUI
import BodyCore

// Small building blocks reused across the MuscleLab page.

/// The rounded dark card every section sits in.
///
/// A `ViewModifier` bundles several modifiers under one name, a bit like a reusable
/// styled wrapper component in React. Use it as `.labCard()`.
struct LabCardModifier: ViewModifier {
    var tint: Color? = nil
    var border: Color? = nil

    @Environment(\.bodyTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .fill(tint ?? theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(border ?? theme.cardBorder, lineWidth: theme.cardBorderWidth)
            )
    }
}

extension View {
    func labCard(tint: Color? = nil, border: Color? = nil) -> some View {
        modifier(LabCardModifier(tint: tint, border: border))
    }
}

/// Small uppercase heading above a group of cards ("HIGHLIGHTS").
struct SectionTitle: View {
    let text: String
    var icon: String? = nil
    var color: Color? = nil

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(theme.stats.sectionFont)
        .tracking(theme.stats.sectionTracking)
        .textCase(.uppercase)
        .foregroundStyle(color ?? theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One colored slice of a ring.
struct RingSegment: Identifiable {
    let id: String
    let color: Color
    /// Fraction of the full circle (all segments should add up to about 1).
    let share: Double
}

/// A donut made of colored segments with rounded ends, like an Activity ring split into parts.
/// `progress` (0–1) grows every segment from 12 o'clock, which is what animates on appear.
struct SplitRing: View {
    let segments: [RingSegment]
    let lineWidth: CGFloat
    var progress: Double = 1
    /// Defaults to the theme's ring track.
    var track: Color? = nil

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(min(geometry.size.width, geometry.size.height) - lineWidth, 1)
            // Round caps stick out half a line width past each end; leave room for them plus a small gap.
            let gap = segments.count > 1 ? (lineWidth * 1.35) / (.pi * diameter) : 0

            ZStack {
                Circle().stroke(track ?? theme.ringTrack, lineWidth: lineWidth)
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let start = segments[..<index].reduce(0) { $0 + $1.share } * progress
                    let end = start + segment.share * progress
                    if end - start > gap {
                        // `trim` draws only part of a shape's outline: here, one arc of the circle.
                        Circle()
                            .trim(from: start + gap / 2, to: end - gap / 2)
                            .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(-90))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

/// A tiny pie showing one share (used in the exercise list).
struct MiniPie: View {
    let share: Double
    let color: Color
    var size: CGFloat = 18

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.ringTrack)
            Circle()
                .trim(from: 0, to: share)
                .stroke(color, lineWidth: size / 2)
                .frame(width: size / 2, height: size / 2)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// A capsule-shaped segmented switch with a sliding orange thumb.
/// Used for Stats / Lab and for Full / Push / Pull / Legs / Core.
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var compact: Bool
    var animation: Animation
    let label: (Value) -> String
    var icon: (Value) -> String?
    /// Shows a small dot under an option (e.g. "trained today").
    var badge: (Value) -> Bool

    /// `@Namespace` gives `matchedGeometryEffect` an id space so one thumb view can glide
    /// between buttons, instead of each button fading its own background in and out.
    @Namespace private var thumbSpace
    @Environment(\.bodyTheme) private var theme

    init(options: [Value], selection: Binding<Value>, compact: Bool = false, animation: Animation,
         label: @escaping (Value) -> String,
         icon: @escaping (Value) -> String? = { _ in nil },
         badge: @escaping (Value) -> Bool = { _ in false }) {
        self.options = options
        self._selection = selection
        self.compact = compact
        self.animation = animation
        self.label = label
        self.icon = icon
        self.badge = badge
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(animation) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        if let name = icon(option) { Image(systemName: name) }
                        Text(label(option))
                    }
                    .font(compact ? theme.chipFont : theme.pillFont)
                    .foregroundStyle(isOn ? theme.onAccent : theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 34 : theme.toggleHeight)
                    .overlay(alignment: .bottom) {
                        if badge(option) {
                            Circle()
                                .fill(isOn ? theme.onAccent : theme.accent)
                                .frame(width: 4, height: 4)
                                .padding(.bottom, 2)
                        }
                    }
                    .background {
                        if isOn {
                            Capsule()
                                .fill(theme.accent)
                                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.chipBackground))
        .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
    }
}

/// The ring under each day in the week strip and the calendar: the day's split, or an empty track.
struct DayRing: View {
    let analysis: WorkoutAnalysis?
    var size: CGFloat = 38
    var dimmed = false

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        SplitRing(segments: segments, lineWidth: theme.miniRingWidth,
                  track: dimmed ? theme.futureRingTrack : nil)
            .frame(width: size, height: size)
    }

    private var segments: [RingSegment] {
        guard let analysis else { return [] }
        return analysis.split.map { RingSegment(id: $0.part.rawValue, color: theme.color(for: $0.part), share: $0.share) }
    }
}

/// Thin tabs with a sliding orange underline (Stats / Lab). Lighter than a filled pill,
/// so the orange stays reserved for data.
struct UnderlineTabs<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var animation: Animation
    let label: (Value) -> String
    var icon: (Value) -> String?

    @Namespace private var underlineSpace
    @Environment(\.bodyTheme) private var theme

    init(options: [Value], selection: Binding<Value>, animation: Animation,
         label: @escaping (Value) -> String, icon: @escaping (Value) -> String? = { _ in nil }) {
        self.options = options
        self._selection = selection
        self.animation = animation
        self.label = label
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(animation) { selection = option }
                } label: {
                    HStack(spacing: 8) {
                        if let name = icon(option) {
                            Image(systemName: name)
                                .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
                        }
                        Text(label(option))
                            .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
                    }
                    .font(theme.tabFont)
                    .frame(maxWidth: .infinity)
                    .frame(height: theme.tabHeight)
                    .overlay(alignment: .bottom) {
                        if isOn {
                            Rectangle()
                                .fill(theme.accent)
                                .frame(height: theme.tabUnderlineHeight)
                                .matchedGeometryEffect(id: "underline", in: underlineSpace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 16)
        // Full-width hairline the underline sits on.
        .background(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }
}
