import SwiftUI

/// Turns SVG path data (the `d="..."` attribute) into a SwiftUI `Path`.
///
/// Supported commands, absolute (uppercase) and relative (lowercase):
///   M/m move, L/l line, H/h horizontal line, V/v vertical line,
///   C/c cubic curve, S/s smooth cubic, Q/q quadratic curve, T/t smooth quadratic, Z/z close.
/// Arcs (A/a) are not supported: convert them to curves in your editor (see docs/ART_GUIDE.md).
///
/// `Path` is SwiftUI's vector outline type (like a Path2D in the browser canvas API).
public enum SVGPathParser: Sendable {

    public enum ParseError: Error, CustomStringConvertible, Sendable {
        case unsupportedCommand(Character)
        case expectedNumber(command: Character, offset: Int)
        case missingMoveTo
        case unexpectedCharacter(Character, offset: Int)

        public var description: String {
            switch self {
            case .unsupportedCommand(let c):
                "Unsupported SVG path command '\(c)'. Convert arcs/shapes to plain curves before exporting."
            case .expectedNumber(let c, let offset):
                "Command '\(c)' is missing numbers (at character \(offset))."
            case .missingMoveTo:
                "Path data must start with an M/m command."
            case .unexpectedCharacter(let c, let offset):
                "Unexpected character '\(c)' at \(offset)."
            }
        }
    }

    public static func parse(_ data: String) throws -> Path {
        var tokens = Tokenizer(data)
        var path = Path()

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?   // for S/s reflection
        var lastQuadControl: CGPoint?    // for T/t reflection
        var command: Character?

        while !tokens.isAtEnd {
            if let next = tokens.nextCommand() {
                command = next
            } else if command == nil || command == "Z" || command == "z" {
                // Numbers with no command before them (or right after a close).
                if command == nil { throw ParseError.missingMoveTo }
                throw ParseError.unexpectedCharacter(tokens.peekCharacter, offset: tokens.offset)
            }
            // Otherwise: more numbers after a command = repeat that command (SVG allows this).

            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            let origin = relative ? current : .zero

            func point() throws -> CGPoint {
                let x = try tokens.number(for: cmd)
                let y = try tokens.number(for: cmd)
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }

            var isCubic = false
            var isQuad = false

            switch cmd {
            case "M", "m":
                let p = try point()
                path.move(to: p)
                current = p
                subpathStart = p
                // Extra coordinate pairs after a move are treated as lines.
                command = relative ? "l" : "L"

            case "L", "l":
                let p = try point()
                path.addLine(to: p)
                current = p

            case "H", "h":
                let x = try tokens.number(for: cmd)
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)

            case "V", "v":
                let y = try tokens.number(for: cmd)
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)

            case "C", "c":
                let c1 = try point(), c2 = try point(), p = try point()
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCubicControl = c2
                current = p
                isCubic = true

            case "S", "s":
                let c1 = reflect(lastCubicControl, around: current)
                let c2 = try point(), p = try point()
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCubicControl = c2
                current = p
                isCubic = true

            case "Q", "q":
                let c = try point(), p = try point()
                path.addQuadCurve(to: p, control: c)
                lastQuadControl = c
                current = p
                isQuad = true

            case "T", "t":
                let c = reflect(lastQuadControl, around: current)
                let p = try point()
                path.addQuadCurve(to: p, control: c)
                lastQuadControl = c
                current = p
                isQuad = true

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart

            default:
                throw ParseError.unsupportedCommand(cmd)
            }

            if !isCubic { lastCubicControl = nil }
            if !isQuad { lastQuadControl = nil }
        }
        return path
    }

    /// Smooth curves (S/T) mirror the previous control point through the current point.
    private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }
}

/// Splits path data into command letters and numbers.
/// Handles the compact forms editors emit, like "M10-5.5.5" (= M 10 -5.5 0.5).
private struct Tokenizer {
    private let bytes: [UInt8]
    public private(set) var offset = 0

    public init(_ string: String) { bytes = Array(string.utf8) }

    public var isAtEnd: Bool {
        mutating get {
            skipSeparators()
            return offset >= bytes.count
        }
    }

    public var peekCharacter: Character {
        offset < bytes.count ? Character(UnicodeScalar(bytes[offset])) : " "
    }

    /// Returns the next command letter, or nil if the next token is a number.
    public mutating func nextCommand() -> Character? {
        skipSeparators()
        guard offset < bytes.count else { return nil }
        let byte = bytes[offset]
        let isLetter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
        // 'e'/'E' only appear inside numbers, which are consumed by `number`.
        guard isLetter else { return nil }
        offset += 1
        return Character(UnicodeScalar(byte))
    }

    public mutating func number(for command: Character) throws -> CGFloat {
        skipSeparators()
        let start = offset
        if offset < bytes.count, bytes[offset] == plus || bytes[offset] == minus { offset += 1 }
        var sawDigit = false
        var sawDot = false
        while offset < bytes.count {
            let b = bytes[offset]
            if isDigit(b) {
                sawDigit = true
            } else if b == dot && !sawDot {
                sawDot = true
            } else {
                break
            }
            offset += 1
        }
        // Exponent, e.g. 1e-3
        if sawDigit, offset < bytes.count, bytes[offset] == 101 || bytes[offset] == 69 {
            var probe = offset + 1
            if probe < bytes.count, bytes[probe] == plus || bytes[probe] == minus { probe += 1 }
            if probe < bytes.count, isDigit(bytes[probe]) {
                offset = probe
                while offset < bytes.count, isDigit(bytes[offset]) { offset += 1 }
            }
        }
        guard sawDigit,
              let text = String(bytes: bytes[start..<offset], encoding: .ascii),
              let value = Double(text)
        else {
            offset = start
            throw SVGPathParser.ParseError.expectedNumber(command: command, offset: start)
        }
        return CGFloat(value)
    }

    private mutating func skipSeparators() {
        while offset < bytes.count {
            switch bytes[offset] {
            case 32, 9, 10, 13, 44: offset += 1   // space, tab, newline, return, comma
            default: return
            }
        }
    }

    private func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
    private let plus: UInt8 = 43, minus: UInt8 = 45, dot: UInt8 = 46
}
