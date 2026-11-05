import SwiftUI
import BodyCore

/// One label beside the figure: a muscle's name and number, joined to the muscle by a thin line.
struct MuscleLabel: Identifiable {
    let muscle: MuscleID
    /// True for the left column, false for the right.
    let onLeft: Bool
    /// Where the leader line touches the muscle, in points.
    let anchor: CGPoint
    /// Vertical center of the label text, in points.
    var y: CGFloat

    var id: MuscleID { muscle }
}

/// Works out where every label goes. Pure layout math, no drawing.
///
/// Each muscle gets one label. Muscles are sorted top to bottom and alternate between the
/// left and right columns, so both columns stay about equally full. Within a column, each
/// label starts level with its muscle and is nudged down (or up) just enough not to overlap.
enum LabelLayout {
    /// - Parameters:
    ///   - only: when set, only this group's muscles get labels.
    ///   - muscles: when set, only these muscles get labels.
    static func labels(art: FigureArt, only: MuscleGroup? = nil, muscles allowed: Set<MuscleID>? = nil, figureRect rect: CGRect, columnTop: CGFloat,
                       columnBottom: CGFloat, rowHeight: CGFloat) -> [MuscleLabel] {
        guard rect.width > 0 else { return [] }

        // Muscles in this view, in top-to-bottom order of where they're drawn.
        let muscles = Set(art.regions.map(\.muscle).filter { (only == nil || $0.group == only) && (allowed?.contains($0) ?? true) })
            .map { ($0, bounds(of: $0, in: art, half: nil).midY) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        var left: [MuscleLabel] = []
        var right: [MuscleLabel] = []
        for (index, muscle) in muscles.enumerated() {
            let onLeft = index.isMultiple(of: 2)
            let box = bounds(of: muscle, in: art, half: onLeft ? .left : .right)
            let anchor = CGPoint(x: rect.minX + box.midX * rect.width, y: rect.minY + box.midY * rect.height)
            let label = MuscleLabel(muscle: muscle, onLeft: onLeft, anchor: anchor, y: anchor.y)
            if onLeft { left.append(label) } else { right.append(label) }
        }

        return spread(left, top: columnTop, bottom: columnBottom, rowHeight: rowHeight)
            + spread(right, top: columnTop, bottom: columnBottom, rowHeight: rowHeight)
    }

    private enum ScreenHalf { case left, right }

    /// Bounding box (normalized) of a muscle's shapes, optionally only those on one half of the screen.
    private static func bounds(of muscle: MuscleID, in art: FigureArt, half: ScreenHalf?) -> CGRect {
        let all = art.regions.filter { $0.muscle == muscle }
        let onHalf = all.filter { region in
            switch half {
            case .left: region.bounds.midX <= 0.5
            case .right: region.bounds.midX >= 0.5
            case nil: true
            }
        }
        let chosen = onHalf.isEmpty ? all : onHalf
        return chosen.dropFirst().reduce(chosen.first?.bounds ?? .zero) { $0.union($1.bounds) }
    }

    /// Spreads labels so they're at least `rowHeight` apart, staying between `top` and `bottom`.
    ///
    /// Labels that would overlap are merged into a "cluster" that is centered on the average
    /// of its muscles' heights, so a crowded area spreads both up and down instead of only down.
    private static func spread(_ labels: [MuscleLabel], top: CGFloat, bottom: CGFloat,
                               rowHeight: CGFloat) -> [MuscleLabel] {
        let sorted = labels.sorted { $0.y < $1.y }
        // Each cluster is a run of consecutive labels stacked `rowHeight` apart, starting at `start`.
        var clusters: [(labels: [MuscleLabel], start: CGFloat)] = []

        for label in sorted {
            clusters.append(([label], label.y))
            // Merge with the cluster above while the two overlap.
            while clusters.count > 1 {
                let last = clusters[clusters.count - 1]
                let previous = clusters[clusters.count - 2]
                let previousEnd = previous.start + CGFloat(previous.labels.count) * rowHeight
                guard previousEnd > last.start else { break }
                let merged = previous.labels + last.labels
                let averageTarget = merged.map(\.y).reduce(0, +) / CGFloat(merged.count)
                let start = averageTarget - CGFloat(merged.count - 1) * rowHeight / 2
                clusters.removeLast(2)
                clusters.append((merged, start))
            }
        }

        var result: [MuscleLabel] = []
        for cluster in clusters {
            for (index, var label) in cluster.labels.enumerated() {
                label.y = cluster.start + CGFloat(index) * rowHeight
                result.append(label)
            }
        }

        // Keep everything on screen: nudge down from the top, then up from the bottom.
        let half = rowHeight / 2
        for i in result.indices {
            result[i].y = max(result[i].y, i == 0 ? top + half : result[i - 1].y + rowHeight)
        }
        for i in result.indices.reversed() {
            result[i].y = min(result[i].y, i == result.count - 1 ? bottom - half : result[i + 1].y - rowHeight)
        }
        return result
    }
}

/// Draws the labels and their leader lines. Tapping a label selects its muscle.
struct MuscleLabelsView: View {
    let labels: [MuscleLabel]
    let renderer: FigureRenderer
    /// Custom text per muscle; nil shows the value × 100.
    var labelText: [MuscleID: String]? = nil
    let columnWidth: CGFloat
    /// Gap between the screen edge and each label column.
    let edgePadding: CGFloat
    let rowHeight: CGFloat
    let size: CGSize
    var onTap: (MuscleID) -> Void

    @Environment(\.bodyTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for label in labels {
                    let e = renderer.visibility(of: label.muscle)
                    let color = label.muscle == renderer.selected ? theme.selectionColor : theme.leaderLineColor
                    var line = Path()
                    let inner = edgePadding + columnWidth
                    line.move(to: CGPoint(x: label.onLeft ? inner + 2 : size.width - inner - 2, y: label.y))
                    line.addLine(to: label.anchor)
                    context.stroke(line, with: .color(color.opacity(e)), lineWidth: theme.leaderLineWidth)

                    let d = theme.leaderDotSize
                    let dot = Path(ellipseIn: CGRect(x: label.anchor.x - d / 2, y: label.anchor.y - d / 2, width: d, height: d))
                    context.fill(dot, with: .color(color.opacity(e)))
                }
            }

            ForEach(labels) { label in
                labelText(label)
                    .frame(width: columnWidth, height: rowHeight,
                           alignment: label.onLeft ? .trailing : .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(label.muscle) }
                    // `.position` places the view's center at a point, like `position: absolute` + transform.
                    .position(x: label.onLeft ? edgePadding + columnWidth / 2 : size.width - edgePadding - columnWidth / 2,
                              y: label.y)
            }
        }
        .frame(width: size.width, height: size.height)
        // The figure already exposes one VoiceOver element per muscle; don't read every name twice.
        .accessibilityHidden(true)
    }

    private func labelText(_ label: MuscleLabel) -> some View {
        let isSelected = label.muscle == renderer.selected || renderer.highlighted.contains(label.muscle)
        let isPulsing = renderer.pulsing.contains(label.muscle)
        let number = Int((renderer.value(of: label.muscle) * 100).rounded())

        return VStack(alignment: label.onLeft ? .trailing : .leading, spacing: 0) {
            Text(label.muscle.shortName)
                .font(theme.labelNameFont.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(labelText?[label.muscle] ?? "\(number)")
                .font(theme.labelValueFont)
                .foregroundStyle(isPulsing ? theme.pulseColor : theme.labelValueColor)
        }
        .opacity(renderer.visibility(of: label.muscle))
    }
}
