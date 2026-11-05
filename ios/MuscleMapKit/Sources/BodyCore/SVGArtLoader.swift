import SwiftUI

/// Reads `front.svg` / `back.svg` from this package's resources (`Bundle.module`) and turns them into `FigureArt`.
///
/// Naming rules for `<path id="...">` (full details in docs/ART_GUIDE.md):
///   silhouette...            neutral body outline (any id starting with "silhouette")
///   <muscleID>_<L|R|C>       one muscle shape, e.g. "lats_L"
///   <muscleID>_<L|R|C>_<n>   extra shapes for the same muscle/side, e.g. "absLower_L_2"
/// L / R mean the left / right half *of the drawing as you look at it*.
/// If a muscle has `_L` shapes but no `_R` shapes, the right side is made by mirroring.
public enum SVGArtLoader: Sendable {

    /// Loads a bundled SVG from this package.
    public static func load(resource: String, facing: BodyFacing) -> FigureArt {
        load(resource: resource, facing: facing, bundle: .module)
    }

    public static func load(resource: String, facing: BodyFacing, bundle: Bundle) -> FigureArt {
        guard let url = bundle.url(forResource: resource, withExtension: "svg"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Missing \(resource).svg (expected in MuscleMapKit/Sources/BodyCore/Resources/).")
            return FigureArt(facing: facing, aspectRatio: 0.5, silhouette: Path(), regions: [])
        }
        return load(svgData: data, name: resource, facing: facing)
    }

    public static func load(svgData: Data, name: String, facing: BodyFacing) -> FigureArt {
        let document = SVGDocumentReader()
        let parser = XMLParser(data: svgData)
        parser.delegate = document
        parser.parse()

        let canvas = document.viewBox ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        // Maps SVG canvas units into the 0–1 normalized space.
        let normalize = CGAffineTransform(scaleX: 1 / canvas.width, y: 1 / canvas.height)
            .translatedBy(x: -canvas.minX, y: -canvas.minY)
        // Flips the 0–1 space left↔right.
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)

        var silhouette = Path()
        var parsed: [(name: ParsedName, path: Path)] = []

        for element in document.paths {
            let path: Path
            do {
                path = try SVGPathParser.parse(element.d).applying(normalize)
            } catch {
                log("\(name).svg: skipping path '\(element.id)': \(error)")
                continue
            }
            if element.id.hasPrefix("silhouette") {
                silhouette.addPath(path)
            } else if let parsedName = ParsedName(element.id) {
                parsed.append((parsedName, path))
            } else {
                log("\(name).svg: ignoring path with unrecognized id '\(element.id)'")
            }
        }

        // Muscles that have any right-hand shapes are taken as drawn; the rest get mirrored.
        let drawnRight = Set(parsed.filter { $0.name.screenSide == "R" }.map(\.name.muscle))
        var regions: [MuscleRegion] = []

        for (parsedName, path) in parsed {
            regions.append(region(parsedName, screenSide: parsedName.screenSide, path: path, facing: facing))
            if parsedName.screenSide == "L" && !drawnRight.contains(parsedName.muscle) {
                regions.append(region(parsedName, screenSide: "R", path: path.applying(mirror), facing: facing))
            }
        }

        let missing = facing.expectedMuscles.subtracting(regions.map(\.muscle))
        if !missing.isEmpty {
            log("\(name).svg: no art for \(missing.map(\.rawValue).sorted().joined(separator: ", "))")
        }

        return FigureArt(
            facing: facing,
            aspectRatio: canvas.width / canvas.height,
            silhouette: silhouette,
            regions: regions
        )
    }

    private static func region(_ name: ParsedName, screenSide: String, path: Path, facing: BodyFacing) -> MuscleRegion {
        // From the front you see the person's right side on the left of the screen; from the back, their left.
        let side: BodySide = switch (screenSide, facing) {
        case ("C", _): .center
        case ("L", .front), ("R", .back): .right
        default: .left
        }
        let id = [name.muscle.rawValue, screenSide, name.index].compactMap { $0 }.joined(separator: "_")
        return MuscleRegion(id: id, muscle: name.muscle, facing: facing, side: side, path: path)
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[MuscleMap art] \(message)")
        #endif
    }
}

/// "absLower_L_2" → muscle .absLower, screen side "L", index "2".
private struct ParsedName {
    public let muscle: MuscleID
    public let screenSide: String
    public let index: String?

    public init?(_ id: String) {
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count == 2 || parts.count == 3,
              let muscle = MuscleID(rawValue: parts[0]),
              ["L", "R", "C"].contains(parts[1]) else { return nil }
        self.muscle = muscle
        self.screenSide = parts[1]
        self.index = parts.count == 3 ? parts[2] : nil
    }
}

/// Minimal SVG reader: collects the canvas size and every `<path id d>`.
/// Groups, styles and other elements are ignored.
private final class SVGDocumentReader: NSObject, XMLParserDelegate {
    public var viewBox: CGRect?
    public var paths: [(id: String, d: String)] = []

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "svg":
            if let box = attributes["viewBox"] {
                let numbers = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                if numbers.count == 4 {
                    viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                }
            } else if let w = attributes["width"].flatMap(Self.length), let h = attributes["height"].flatMap(Self.length) {
                viewBox = CGRect(x: 0, y: 0, width: w, height: h)
            }
        case "path":
            if let id = attributes["id"], let d = attributes["d"] {
                paths.append((id, d))
            }
        default:
            break
        }
    }

    /// "400px" → 400
    /// `nonisolated`: this app runs code on the main thread by default; pure helpers like this one
    /// opt out so they can be called from anywhere (here, from XMLParser's callbacks).
    private nonisolated static func length(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.").inverted))
    }
}
