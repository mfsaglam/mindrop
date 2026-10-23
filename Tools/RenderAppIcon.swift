// Renders Mindrop's app icon: the search field from the empty list's Spotlight guide, cut
// into a square. The field's rounded left end is inside the icon and the rest runs off the
// right edge; in it, the app's own search icon (Iconsax "search-normal", Linear) and a text
// cursor waiting for a keyword. A grey panel behind, as in the guide.
//
// Usage: swift Tools/RenderAppIcon.swift <output.png> [--template]
//        swift Tools/RenderAppIcon.swift <output.symbolset> --symbol
//
// `--template` renders just the search icon and the cursor, on a transparent background and
// larger in the frame, for the action extension: iOS draws an action extension's icon as a
// mask of its alpha channel, so the app's icon would come out there as a filled square.
//
// `--symbol` writes the search icon and the cursor as a custom SF Symbol, for the Control
// Center control: Control Center draws only symbols. It needs SwiftDraw
// (`brew install swiftdraw`), as the Iconsax symbols do.
//
// The app icon is written without an alpha channel at all: App Store validation rejects a
// large app icon that has one, even when every pixel is opaque.
//
// The search icon is Iconsax's (iconsax.io), free for apps without attribution. Its licence
// does not allow a stock icon to become a registered trademark: if the icon is ever
// registered, the magnifier should be redrawn first.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024.0

/// Iconsax "search-normal", Linear: a 24×24 artboard, stroked 1.5 wide with round ends.
let searchIconPaths = [
    "M11 20C15.9706 20 20 15.9706 20 11C20 6.02944 15.9706 2 11 2C6.02944 2 2 6.02944 2 11C2 15.9706 6.02944 20 11 20Z",
    "M18.8978 20.4629C19.1822 22.1242 20.3546 22.4637 21.4838 21.2188C22.5159 20.0805 22.1195 18.9585 20.5969 18.7278C19.4713 18.5472 18.7052 19.3313 18.8978 20.4629Z",
]
let searchIconStroke = 1.5

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
guard (2...3).contains(arguments.count) else {
    FileHandle.standardError.write(Data("usage: RenderAppIcon.swift <output.png> [--template | --symbol]\n".utf8))
    exit(2)
}
let isTemplate = arguments.count == 3 && arguments[2] == "--template"

// MARK: - Symbol

/// Runs SwiftDraw, failing loudly.
func swiftDraw(_ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftdraw"] + arguments
    do { try process.run() } catch { fatalError("Could not run SwiftDraw: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("SwiftDraw failed") }
}

/// Whether a symbol template's Ultralight, Regular and Black outlines have the same commands,
/// path by path. iOS draws the weights in between by interpolating them; when they differ,
/// Xcode leaves the symbol out without an error.
func interpolatable(_ template: String) -> Bool {
    func commands(_ variant: String) -> [String] {
        guard let group = template.range(of: "(?s)<g id=\"\(variant)-S\"[^>]*>.*?</g>", options: .regularExpression) else { return [] }
        let text = String(template[group])
        let path = try! NSRegularExpression(pattern: "d=\"([^\"]+)\"")
        return path.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            String(text[Range(match.range(at: 1), in: text)!].filter { "MLCZHVQA".contains($0) })
        }
    }
    return commands("Ultralight") == commands("Regular") && commands("Regular") == commands("Black")
}

/// The search icon at 0.8 of its size with the cursor after it, together centred on Iconsax's
/// 24-point grid. Top and bottom keep the margin Mindrop's Iconsax symbols have, so it is as
/// tall as they are; the sides hold the wider shape. Drawn heavier than in the app, as the
/// sketches for the control were: at that weight the handle's little loop closes up, so it is
/// filled.
func writeSymbol(to folder: URL) {
    let stroke = 1.9
    let source = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">
    <g transform="translate(0.1 2.2) scale(0.8)" stroke="#000" stroke-width="\(stroke / 0.8)" stroke-linecap="round" stroke-linejoin="round">
    <path d="\(searchIconPaths[0])"/>
    <path d="\(searchIconPaths[1])" fill="#000"/>
    </g>
    <path d="M22.3 4.15V17.85" stroke="#000" stroke-width="\(stroke)" stroke-linecap="round"/>
    </svg>
    """
    let name = folder.deletingPathExtension().lastPathComponent
    let sourceURL = FileManager.default.temporaryDirectory.appending(path: "\(name).svg")
    let output = folder.appending(path: "\(name).svg")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    } catch { fatalError("Could not write the symbol's source: \(error)") }

    let insets = "4.2,0.5,4.2,0.5"
    let command = [sourceURL.path, "--format", "sfsymbol", "--output", output.path,
                   "--insets", insets, "--ultralight-insets", insets, "--black-insets", insets]
    swiftDraw(command + ["--ultralight-stroke-width", "0.6", "--black-stroke-width", "1.6"])
    if let template = try? String(contentsOf: output, encoding: .utf8), !interpolatable(template) {
        swiftDraw(command)
        print("\(name): one weight only")
    }

    let contents = """
    {
      "info": {
        "author": "xcode",
        "version": 1
      },
      "symbols": [
        {
          "filename": "\(name).svg",
          "idiom": "universal"
        }
      ]
    }

    """
    do { try contents.write(to: folder.appending(path: "Contents.json"), atomically: true, encoding: .utf8) }
    catch { fatalError("Could not write the symbol's Contents.json: \(error)") }
    print("Wrote \(folder.path)")
}

if arguments.count == 3 && arguments[2] == "--symbol" {
    writeSymbol(to: URL(fileURLWithPath: arguments[1]))
    exit(0)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [red / 255, green / 255, blue / 255, alpha])!
}

guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: sRGB,
    bitmapInfo: (isTemplate ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
) else { fatalError("Could not create a bitmap context") }

// Top-left origin, as in the design and in SVG.
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)

func linear(_ colors: [CGColor], from start: CGPoint, to end: CGPoint, locations: [CGFloat]? = nil) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// The search icon centred on `center`, `side` points across, then the cursor after it.
func drawSearchIconAndCursor(center: CGPoint, side: Double, stroke: Double = searchIconStroke, icon: CGColor, cursor: CGColor) {
    let scale = side / 24
    context.saveGState()
    context.translateBy(x: center.x - 12 * scale, y: center.y - 12 * scale)
    context.scaleBy(x: scale, y: scale)
    context.setLineWidth(stroke)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(icon)
    for data in searchIconPaths {
        var parser = PathParser(data)
        context.addPath(parser.parse())
    }
    context.strokePath()
    context.restoreGState()

    let width = side * 0.058 * stroke
    let bar = CGRect(x: center.x + side / 2 + side * 0.23, y: center.y - side * 0.55, width: width, height: side * 1.1)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    context.setFillColor(cursor)
    context.fillPath()
}

if isTemplate {
    // Shifted left so the icon and the cursor together are centred. Drawn heavier: the share
    // sheet shows it small, as a single-colour shape.
    let side = canvas * 0.6
    drawSearchIconAndCursor(center: CGPoint(x: canvas / 2 - side * 0.17, y: canvas / 2), side: side, stroke: 2.4,
                            icon: color(0, 0, 0), cursor: color(0, 0, 0))
} else {
    // The panel: light grey, lighter towards the top left.
    linear([color(240, 240, 244), color(222, 222, 230)], from: .zero, to: CGPoint(x: 0, y: canvas))
    let glow = CGGradient(colorsSpace: sRGB, colors: [color(255, 255, 255, 0.18), color(255, 255, 255, 0)] as CFArray, locations: nil)!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 180, y: 140), startRadius: 0,
                               endCenter: CGPoint(x: 180, y: 140), endRadius: 620, options: .drawsAfterEndLocation)

    // The field: about two thirds of the icon's height, its left end inside, running off the right.
    let height = 656.0, left = 130.0
    let field = CGRect(x: left, y: (canvas - height) / 2, width: canvas + 400, height: height)
    let capsule = CGPath(roundedRect: field, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)

    context.saveGState()
    // Shadow offsets are in device space, where up is positive: this one falls below.
    context.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: color(0, 0, 0, 0.16))
    context.addPath(capsule)
    context.setFillColor(color(246, 246, 250))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(capsule)
    context.clip()
    linear([color(255, 255, 255), color(246, 246, 250)], from: CGPoint(x: 0, y: field.minY), to: CGPoint(x: 0, y: field.maxY))
    linear([color(255, 255, 255, 0.35), color(255, 255, 255, 0)], from: CGPoint(x: 0, y: field.minY), to: CGPoint(x: 0, y: field.midY))
    context.restoreGState()

    // Its glass edge: bright along the top and left, faint below.
    context.saveGState()
    context.addPath(capsule)
    context.setLineWidth(7)
    context.replacePathWithStrokedPath()
    context.clip()
    linear([color(255, 255, 255), color(255, 255, 255, 0.2), color(255, 255, 255, 0.45)],
           from: CGPoint(x: field.minX, y: field.minY), to: CGPoint(x: field.minX + 600, y: field.maxY), locations: [0, 0.6, 1])
    context.restoreGState()

    // The search icon in the field's rounded end, as large against the field as in the app.
    drawSearchIconAndCursor(center: CGPoint(x: left + height / 2, y: canvas / 2), side: height * 0.46,
                            icon: color(120, 120, 128), cursor: color(20, 20, 24))
}

guard let image = context.makeImage() else { fatalError("Could not render the icon") }
let output = URL(fileURLWithPath: arguments[1])
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("Could not open \(output.path) for writing") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path)")
