import SwiftUI
import BodyCore

/// The main reusable view: one side (front or back) of the anatomical figure.
/// It owns no data; everything comes in through its inputs (like props in React).
struct BodyFigureView: View {
    /// 0–1 per muscle. Missing muscles count as 0.
    var values: [MuscleID: Double]
    var pulsing: Set<MuscleID>
    var selected: MuscleID?
    var side: BodyFacing
    /// Muscles outlined together (e.g. all chest muscles when "Chest" is picked from a list).
    var highlighted: Set<MuscleID> = []
    /// Custom label text per muscle (e.g. "9.5 sets"). When set, only these muscles get labels.
    /// When nil, every muscle is labelled with its value × 100.
    var labelText: [MuscleID: String]? = nil
    /// Men's or women's figure.
    var bodyType: BodyType = .male
    /// When set, only this group's muscles are shown, and the figure moves and scales to focus on them.
    var groupFilter: MuscleGroup? = nil
    var onTap: (MuscleID) -> Void
    /// Called when the user taps somewhere that isn't a muscle (used to deselect).
    var onTapBackground: () -> Void = {}

    @Environment(\.bodyTheme) private var theme

    /// The last group that was focused. When the filter goes back to "All", the muscles of
    /// this group are the ones that stay visible while everything else fades back in.
    @State private var lastGroup: MuscleGroup?

    /// Taps this close (in points) to a muscle's edge still count, so thin muscles are hittable.
    private let hitTolerance: CGFloat = 6
    /// Width of each label column (left and right of the figure).
    private let labelColumnWidth: CGFloat = 80
    /// Gap between the screen edge and each label column.
    private let labelEdgePadding: CGFloat = 10
    /// Vertical room for one label (name + number).
    private let labelRowHeight: CGFloat = 30
    /// Focusing on a group scales the figure up at most this much.
    private let maxFocusZoom: CGFloat = 2

    private var art: FigureArt { FigureArt.art(for: side, bodyType: bodyType) }

    /// The shapes that can currently be seen and tapped.
    private var visibleRegions: [MuscleRegion] {
        art.regions.filter { groupFilter == nil || $0.muscle.group == groupFilter }
    }

    var body: some View {
        // GeometryReader hands us the space we've been given, so we can size the figure to it.
        GeometryReader { geometry in
            let size = geometry.size
            let sideSpace = labelEdgePadding + labelColumnWidth + 8
            let figureArea = CGRect(x: sideSpace, y: 8, width: size.width - 2 * sideSpace, height: size.height - 16)
            let rect = FigureRenderer.figureRect(in: figureArea, art: art, focusOn: focusBox,
                                                 maxZoom: maxFocusZoom)

            FigureLayers(
                rect: rect,
                focus: groupFilter == nil ? 0 : 1,
                size: size,
                art: art, values: values, pulsing: pulsing, selected: selected, highlighted: highlighted,
                focusGroup: groupFilter ?? lastGroup, labelGroup: groupFilter, labelText: labelText,
                columnWidth: labelColumnWidth, edgePadding: labelEdgePadding,
                rowHeight: labelRowHeight, onTap: onTap)
            .animation(theme.focusAnimation, value: groupFilter)
            .animation(theme.selectionAnimation, value: selected)
            .overlay {
                if let groupFilter, visibleRegions.isEmpty {
                    Text("No \(groupFilter.displayName) muscles on the \(side.displayName.lowercased())")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, figureRect: rect)
            }
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                accessibilityElements(figureRect: rect, size: size)
            }
        }
        // `onChange` runs code after a value changes, like a `useEffect` with that value as its dependency.
        .onChange(of: groupFilter) { _, newGroup in
            if let newGroup { lastGroup = newGroup }
        }
    }

    /// Normalized box around the focused group's shapes (with a little margin), or nil for the whole body.
    private var focusBox: CGRect? {
        guard groupFilter != nil, let first = visibleRegions.first else { return nil }
        let box = visibleRegions.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
        return box.insetBy(dx: -0.03, dy: -0.03)
    }

    // MARK: Hit-testing

    private func handleTap(at location: CGPoint, figureRect rect: CGRect) {
        if let region = region(at: location, figureRect: rect) {
            onTap(region.muscle)
        } else {
            onTapBackground()
        }
    }

    /// Finds the muscle under a tap using the real shapes, not their bounding boxes.
    private func region(at location: CGPoint, figureRect rect: CGRect) -> MuscleRegion? {
        guard rect.width > 0, rect.height > 0 else { return nil }

        // 1. Exact hit: is the point inside the shape? (Done in normalized space.)
        let point = CGPoint(x: (location.x - rect.minX) / rect.width, y: (location.y - rect.minY) / rect.height)
        let exact = visibleRegions.filter { $0.bounds.contains(point) && $0.path.contains(point) }
        if let best = exact.min(by: { $0.area < $1.area }) {
            return best
        }

        // 2. Near miss: accept taps within `hitTolerance` points of a shape's outline.
        let toPoints = CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY)
        let near = visibleRegions.filter { region in
            let shape = region.path.applying(toPoints)
            guard shape.boundingRect.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(location) else { return false }
            return shape.strokedPath(StrokeStyle(lineWidth: hitTolerance * 2)).contains(location)
        }
        return near.min(by: { $0.area < $1.area })
    }

    // MARK: Accessibility

    /// One VoiceOver element per muscle per side (e.g. "Right Abs (Upper)" covers both of its blocks).
    @ViewBuilder
    private func accessibilityElements(figureRect rect: CGRect, size: CGSize) -> some View {
        let items = accessibilityItems(figureRect: rect)
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let value = Int((values[item.muscle] ?? 0) * 100)
                Rectangle()
                    .frame(width: item.frame.width, height: item.frame.height)
                    .offset(x: item.frame.minX, y: item.frame.minY)
                    .accessibilityLabel(item.side.spokenPrefix + item.muscle.displayName)
                    .accessibilityValue("\(value) percent" + (pulsing.contains(item.muscle) ? ", needs work" : ""))
                    .accessibilityAddTraits(item.muscle == selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onTap(item.muscle) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private struct AccessibilityItem {
        let id: String
        let muscle: MuscleID
        let side: BodySide
        var frame: CGRect
    }

    private func accessibilityItems(figureRect rect: CGRect) -> [AccessibilityItem] {
        var items: [AccessibilityItem] = []
        for region in visibleRegions {
            let frame = CGRect(x: rect.minX + region.bounds.minX * rect.width,
                               y: rect.minY + region.bounds.minY * rect.height,
                               width: region.bounds.width * rect.width,
                               height: region.bounds.height * rect.height)
            let id = "\(region.muscle.rawValue)-\(region.side.rawValue)"
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].frame = items[index].frame.union(frame)
            } else {
                items.append(AccessibilityItem(id: id, muscle: region.muscle, side: region.side, frame: frame))
            }
        }
        // Read top-to-bottom, then left-to-right.
        return items.sorted { ($0.frame.midY.rounded(), $0.frame.minX) < ($1.frame.midY.rounded(), $1.frame.minX) }
    }
}

/// Everything that moves when the focus changes: both canvases and the labels.
///
/// `Animatable` lets SwiftUI animate our own properties: during an animation it sets
/// `animatableData` to in-between values every frame and re-runs `body`. So the figure's
/// rect and the fade are smoothly interpolated, and the labels and leader lines follow along.
private struct FigureLayers: View, Animatable {
    var rect: CGRect
    var focus: Double
    /// Animated too, so labels move smoothly when the figure's container grows or shrinks.
    var size: CGSize

    let art: FigureArt
    let values: [MuscleID: Double]
    let pulsing: Set<MuscleID>
    let selected: MuscleID?
    let highlighted: Set<MuscleID>
    let focusGroup: MuscleGroup?
    /// Only this group gets labels (nil = every muscle).
    let labelGroup: MuscleGroup?
    let labelText: [MuscleID: String]?
    let columnWidth: CGFloat
    let edgePadding: CGFloat
    let rowHeight: CGFloat
    let onTap: (MuscleID) -> Void

    @Environment(\.bodyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<Double, CGSize.AnimatableData>> {
        get { AnimatablePair(rect.animatableData, AnimatablePair(focus, size.animatableData)) }
        set {
            rect.animatableData = newValue.first
            focus = newValue.second.first
            size.animatableData = newValue.second.second
        }
    }

    var body: some View {
        let renderer = FigureRenderer(
            art: art, values: values, pulsing: pulsing, selected: selected, highlighted: highlighted,
            focusGroup: focusGroup, focus: focus, theme: theme, rect: rect)
        let labelled = labelText.map { Set($0.keys) }
        let labels = LabelLayout.labels(art: art, only: labelGroup, muscles: labelled, figureRect: rect, columnTop: 0,
                                        columnBottom: size.height, rowHeight: rowHeight)

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                renderer.drawBase(in: &context)
            }

            // TimelineView re-runs its content every display frame while not paused.
            TimelineView(.animation(paused: !renderer.needsAnimation(reduceMotion: reduceMotion))) { timeline in
                Canvas { context, _ in
                    renderer.drawAnimated(in: &context,
                                          time: timeline.date.timeIntervalSinceReferenceDate,
                                          reduceMotion: reduceMotion)
                }
            }
            .drawingGroup() // render this layer on the GPU, since it redraws every frame

            MuscleLabelsView(labels: labels, renderer: renderer, labelText: labelText, columnWidth: columnWidth,
                             edgePadding: edgePadding, rowHeight: rowHeight, size: size, onTap: onTap)
        }
        .frame(width: size.width, height: size.height)
    }
}

#Preview {
    BodyFigureView(
        values: Dictionary(uniqueKeysWithValues: MuscleID.allCases.map { ($0, Double.random(in: 0...1)) }),
        pulsing: [.lats, .glutes],
        selected: .upperChest,
        side: .front,
        onTap: { _ in })
    .background(BodyTheme.standard.background)
}
