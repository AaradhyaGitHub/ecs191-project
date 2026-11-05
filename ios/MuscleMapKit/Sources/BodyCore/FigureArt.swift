import SwiftUI

/// Everything needed to draw one view (front or back) of the figure.
/// Loaded once from `Art/front.svg` and `Art/back.svg`; no logic lives here.
public struct FigureArt: Sendable {
    public let facing: BodyFacing
    /// Width / height of the original artwork, so the figure is never stretched.
    public let aspectRatio: CGFloat
    /// Neutral, non-tappable body outline (head, hands, knees, ...), normalized 0–1.
    public let silhouette: Path
    /// Every muscle shape, in drawing order.
    public let regions: [MuscleRegion]

    // `static let` is computed lazily the first time it's used, then cached for the app's lifetime.
    public static let maleFront = SVGArtLoader.load(resource: "front", facing: .front)
    public static let maleBack = SVGArtLoader.load(resource: "back", facing: .back)
    public static let femaleFront = SVGArtLoader.load(resource: "front_female", facing: .front)
    public static let femaleBack = SVGArtLoader.load(resource: "back_female", facing: .back)

    public static func art(for facing: BodyFacing, bodyType: BodyType = .male) -> FigureArt {
        switch (bodyType, facing) {
        case (.male, .front): maleFront
        case (.male, .back): maleBack
        case (.female, .front): femaleFront
        case (.female, .back): femaleBack
        }
    }
}
