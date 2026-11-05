import SwiftUI
import BodyCore

/// Draws the figure into a `Canvas`. All figure drawing lives here; BodyFigureView
/// only handles layout, labels, taps and accessibility.
///
/// Drawing is split into two layers for performance:
///  * `drawBase`: silhouette, muscle fills and outlines, selection. Redrawn only when inputs change.
///  * `drawAnimated`: only the pulsing muscles. This is the only part redrawn every frame.
struct FigureRenderer {
    let art: FigureArt
    let values: [MuscleID: Double]
    let pulsing: Set<MuscleID>
    let selected: MuscleID?
    /// Muscles outlined together, e.g. every chest muscle when "Chest" is picked from a list.
    var highlighted: Set<MuscleID> = []
    /// The group being focused (or being un-focused, while that animation runs).
    let focusGroup: MuscleGroup?
    /// 0 = whole body shown, 1 = only `focusGroup` shown. In between while animating.
    let focus: Double
    let theme: BodyTheme
    /// Where the art's full canvas (normalized 0–1) sits on screen, in points.
    let rect: CGRect

    // MARK: Layout helpers

    /// Converts normalized (0–1) art space into points inside `rect`.
    var toPoints: CGAffineTransform {
        CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY)
    }

    /// Places the art so the *body* (the silhouette, not the art's empty margins) is as large
    /// as possible inside `available`, centered.
    ///
    /// With `focusOn` (a normalized box, e.g. around the Push muscles), that box is fitted
    /// instead, so the figure scales up and centers on it, but never more than `maxZoom`
    /// times the whole-body size.
    static func figureRect(in available: CGRect, art: FigureArt, focusOn focusBox: CGRect? = nil,
                           maxZoom: CGFloat = 2) -> CGRect {
        let body = art.silhouette.boundingRect
        guard available.width > 0, available.height > 0, body.width > 0, body.height > 0,
              art.aspectRatio > 0 else { return .zero }

        /// Full-canvas width that makes `box` fill `available` in one direction.
        func fittedWidth(_ box: CGRect) -> CGFloat {
            min(available.width / box.width, available.height * art.aspectRatio / box.height)
        }

        var box = body
        var width = fittedWidth(body)
        if let focusBox, focusBox.width > 0, focusBox.height > 0 {
            box = focusBox
            width = min(fittedWidth(focusBox), width * maxZoom)
        }
        let height = width / art.aspectRatio
        return CGRect(x: available.midX - box.midX * width,
                      y: available.midY - box.midY * height,
                      width: width, height: height)
    }

    func value(of muscle: MuscleID) -> Double {
        min(max(values[muscle] ?? 0, 0), 1)
    }

    /// Opacity for a muscle: 1 normally, fading to 0 for muscles outside the focused group.
    func visibility(of muscle: MuscleID) -> Double {
        guard let focusGroup, muscle.group != focusGroup else { return 1 }
        return 1 - focus
    }

    /// The silhouette fades out along with the unfocused muscles.
    var silhouetteVisibility: Double {
        focusGroup == nil ? 1 : 1 - focus
    }

    func needsAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion && !pulsing.isEmpty
    }

    // MARK: Static layer

    func drawBase(in context: inout GraphicsContext) {
        guard rect.width > 0 else { return }

        if silhouetteVisibility > 0 {
            let silhouette = art.silhouette.applying(toPoints)
            context.fill(silhouette, with: .color(theme.silhouetteFill.opacity(silhouetteVisibility)))
            context.stroke(silhouette, with: .color(theme.silhouetteStroke.opacity(silhouetteVisibility)),
                           lineWidth: theme.silhouetteLineWidth)
        }

        for region in art.regions {
            let e = visibility(of: region.muscle)
            guard e > 0 else { continue }
            let path = region.path.applying(toPoints)
            context.fill(path, with: muscleFill(value: value(of: region.muscle), visibility: e,
                                                bounds: path.boundingRect))
            context.stroke(path, with: .color(theme.muscleStroke.opacity(e)), lineWidth: theme.muscleLineWidth)
        }

        for region in art.regions where highlighted.contains(region.muscle) && region.muscle != selected {
            let e = visibility(of: region.muscle)
            guard e > 0 else { continue }
            context.stroke(region.path.applying(toPoints), with: .color(theme.highlightColor.opacity(e)),
                           lineWidth: theme.highlightLineWidth)
        }

        if let selected {
            for region in art.regions where region.muscle == selected && visibility(of: selected) > 0 {
                context.stroke(region.path.applying(toPoints), with: .color(theme.selectionColor),
                               lineWidth: theme.selectionLineWidth)
            }
        }
    }

    /// A muscle with no work gets the flat resting color. Otherwise its value color, as a
    /// top-to-bottom gradient (lighter at the top) so the muscles look a little rounded.
    private func muscleFill(value v: Double, visibility e: Double, bounds: CGRect) -> GraphicsContext.Shading {
        guard v > 0 else { return .color(theme.restingMuscleFill.opacity(e)) }
        let base = theme.colorScale.rgb(at: v)
        let top = base.mixed(with: ColorScale.RGB(hex: 0xFFFFFF), theme.muscleShading)
        let opacity = theme.fillOpacity.lerp(v) * e
        return .linearGradient(Gradient(colors: [top.color.opacity(opacity), base.color.opacity(opacity)]),
                               startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                               endPoint: CGPoint(x: bounds.midX, y: bounds.maxY))
    }

    // MARK: Animated layer

    /// - Parameter time: seconds, from the TimelineView's clock.
    func drawAnimated(in context: inout GraphicsContext, time: TimeInterval, reduceMotion: Bool) {
        guard rect.width > 0, !pulsing.isEmpty else { return }

        // Smooth 0 → 1 → 0 "breath" (a cosine wave), or a frozen level with Reduce Motion.
        let level = reduceMotion
            ? theme.reducedMotionPulseLevel
            : 0.5 - 0.5 * cos(2 * .pi * time / theme.pulseDuration)

        for region in art.regions where pulsing.contains(region.muscle) {
            let e = visibility(of: region.muscle)
            guard e > 0 else { continue }
            let path = region.path.applying(toPoints)
            context.fill(path, with: .color(theme.pulseColor.opacity(theme.pulseFillOpacity * level * e)))
            context.stroke(path, with: .color(theme.pulseColor.opacity((0.3 + 0.7 * level) * e)),
                           lineWidth: theme.pulseLineWidth)
        }
    }
}
