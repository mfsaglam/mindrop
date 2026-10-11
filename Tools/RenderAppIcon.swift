// Renders the app icon from the original Lucide `brain` SVG geometry.
//
// The SVG is parsed rather than redrawn, so the shipped icon is the Lucide path
// data itself: white stroke, solid black background, centred, with generous space.
// Lucide icons are ISC licensed — see Design/LUCIDE-LICENSE.txt.
//
// Usage: swift Tools/RenderAppIcon.swift <input.svg> <output.png> [--template]
//
// `--template` renders the brain on a transparent background and larger in the frame.
// iOS draws an action extension's icon as a mask of its alpha channel, so the app's
// opaque black square would come out as a filled square there.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024.0
let viewBox = 24.0

// MARK: - SVG path parsing

struct PathParser {
    private var tokens: [Substring]
    private var index = 0
    private var current = CGPoint.zero
    private var start = CGPoint.zero
    private var command: Character = "M"
    let path = CGMutablePath()

    init(_ d: String) {
        var spaced = ""
        for character in d {
            if "MmLlHhVvCcSsQqTtAaZz".contains(character) {
                spaced += " \(character) "
            } else if character == "-" {
                spaced += " -"
            } else if character == "," {
                spaced += " "
            } else {
                spaced.append(character)
            }
        }
        tokens = spaced.split(whereSeparator: \.isWhitespace)
    }

    mutating func parse() -> CGPath {
        while index < tokens.count {
            if let letter = tokens[index].first, letter.isLetter {
                command = letter
                index += 1
            }
            switch command {
            case "M", "m":
                let point = nextPoint(relative: command == "m")
                path.move(to: point)
                current = point
                start = point
                command = command == "m" ? "l" : "L"
            case "L", "l":
                let point = nextPoint(relative: command == "l")
                path.addLine(to: point)
                current = point
            case "H", "h":
                let x = number()
                let point = CGPoint(x: command == "h" ? current.x + x : x, y: current.y)
                path.addLine(to: point)
                current = point
            case "V", "v":
                let y = number()
                let point = CGPoint(x: current.x, y: command == "v" ? current.y + y : y)
                path.addLine(to: point)
                current = point
            case "C", "c":
                let relative = command == "c"
                let control1 = nextPoint(relative: relative)
                let control2 = nextPoint(relative: relative)
                let end = nextPoint(relative: relative)
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
            case "A", "a":
                let rx = number(), ry = number(), rotation = number()
                let largeArc = number() != 0, sweep = number() != 0
                let end = nextPoint(relative: command == "a")
                addArc(to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = start
            default:
                fatalError("Unsupported SVG path command: \(command)")
            }
        }
        return path
    }

    private mutating func number() -> Double {
        defer { index += 1 }
        guard index < tokens.count, let value = Double(tokens[index]) else {
            fatalError("Expected a number at token \(index)")
        }
        return value
    }

    private mutating func nextPoint(relative: Bool) -> CGPoint {
        let x = number(), y = number()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    /// Circular-arc support, which is all Lucide's brain needs (rx == ry, no rotation).
    /// Converted to cubic Béziers so the result is independent of the context transform.
    private mutating func addArc(
        to end: CGPoint, rx: Double, ry: Double, rotation: Double, largeArc: Bool, sweep: Bool
    ) {
        precondition(rx == ry && rotation == 0, "Only circular, unrotated arcs are supported")
        let from = current
        guard from != end else { return }

        let halfDeltaX = (from.x - end.x) / 2, halfDeltaY = (from.y - end.y) / 2
        let squaredHalfDistance = halfDeltaX * halfDeltaX + halfDeltaY * halfDeltaY
        // Enlarge the radius if the endpoints are too far apart for it, per the SVG spec.
        let radius = max(rx, sqrt(squaredHalfDistance))
        let factor = sqrt(max(0, radius * radius - squaredHalfDistance) / squaredHalfDistance)
        let sign = largeArc != sweep ? 1.0 : -1.0
        let center = CGPoint(
            x: sign * factor * halfDeltaY + (from.x + end.x) / 2,
            y: sign * factor * -halfDeltaX + (from.y + end.y) / 2
        )

        let startAngle = atan2(from.y - center.y, from.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var sweepAngle = endAngle - startAngle
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let step = sweepAngle / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var angle = startAngle
        for _ in 0..<segments {
            let next = angle + step
            let p1 = point(on: center, radius: radius, angle: angle)
            let p2 = point(on: center, radius: radius, angle: next)
            let t1 = CGPoint(x: -radius * sin(angle), y: radius * cos(angle))
            let t2 = CGPoint(x: -radius * sin(next), y: radius * cos(next))
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + k * t1.x, y: p1.y + k * t1.y),
                control2: CGPoint(x: p2.x - k * t2.x, y: p2.y - k * t2.y)
            )
            angle = next
        }
    }

    private func point(on center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

// MARK: - Rendering

let arguments = CommandLine.arguments
guard (3...4).contains(arguments.count) else {
    FileHandle.standardError.write(Data("usage: RenderAppIcon.swift <input.svg> <output.png> [--template]\n".utf8))
    exit(2)
}
let isTemplate = arguments.count == 4 && arguments[3] == "--template"
/// Fraction of the canvas edge the 24×24 Lucide artboard spans. A template icon is
/// drawn into a tighter frame, since iOS adds its own padding around it.
let symbolScale = isTemplate ? 0.78 : 0.46
let svg = try String(contentsOfFile: arguments[1], encoding: .utf8)
let attribute = try Regex("d=\"([^\"]+)\"")
let pathData = svg.matches(of: attribute).compactMap { $0[1].substring.map(String.init) }
guard !pathData.isEmpty else { fatalError("No path data found in \(arguments[1])") }

let strokeWidth = 2.0  // Lucide's own stroke-width, in artboard units.
let scale = canvas * symbolScale / viewBox
let offset = (canvas - viewBox * scale) / 2

guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create a bitmap context") }

if !isTemplate {
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
}

// Flip to SVG's top-left origin, then place the artboard in the middle of the canvas.
context.translateBy(x: offset, y: canvas - offset)
context.scaleBy(x: scale, y: -scale)

context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(strokeWidth)
context.setLineCap(.round)
context.setLineJoin(.round)
for data in pathData {
    var parser = PathParser(data)
    context.addPath(parser.parse())
    context.strokePath()
}

guard let image = context.makeImage() else { fatalError("Could not render the icon") }
let output = URL(fileURLWithPath: arguments[2])
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("Could not open \(output.path) for writing") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path)")
