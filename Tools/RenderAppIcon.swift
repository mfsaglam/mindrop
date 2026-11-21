// Generates the Mindrop mark assets from the Icon Composer source.
// Run `swift Tools/RenderAppIcon.swift [--check]` with SwiftDraw on PATH.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RenderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

let files = FileManager.default
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let composer = repository.appending(path: "Mindrop/Resources/mindrop_icon.icon")
let artwork = composer.appending(path: "Assets/01-search-mark.svg")
let assetCatalog = "Mindrop/Resources/Assets.xcassets"
let appIcon = "AppIcon.appiconset/AppIcon.png"

func swiftDraw(_ source: URL, format: String, output: URL, options: [String] = []) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftdraw", source.path, "--format", format, "--output", output.path] + options
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw RenderError("SwiftDraw could not render \(source.lastPathComponent).") }
}

func monochromeSVG(width: String, height: String, viewBox: String) throws -> Data {
    let svg = try XMLDocument(contentsOf: artwork)
    guard let root = svg.rootElement() else { throw RenderError("Missing SVG root in \(artwork.lastPathComponent).") }
    root.attribute(forName: "width")?.stringValue = width
    root.attribute(forName: "height")?.stringValue = height
    root.attribute(forName: "viewBox")?.stringValue = viewBox
    for paint in try root.nodes(forXPath: "//@fill | //@stroke") where paint.stringValue != "none" {
        paint.stringValue = "#000000"
    }
    return svg.xmlData(options: .nodePrettyPrint)
}

func opaquePNG(mark: CGImage, background: CGColor, size: Int) throws -> Data {
    guard let colorSpace = background.colorSpace,
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw RenderError("Could not create an opaque bitmap.") }

    let frame = CGRect(x: 0, y: 0, width: size, height: size)
    context.setFillColor(background)
    context.fill(frame)
    context.interpolationQuality = .high
    context.draw(mark, in: frame)

    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { throw RenderError("Could not create the PNG destination.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw RenderError("Could not write PNG data.") }
    return data as Data
}

func backgroundColor() throws -> CGColor {
    let data = try Data(contentsOf: composer.appending(path: "icon.json"))
    let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let fills = document?["fill-specializations"] as? [[String: Any]]
    let base = fills?.first { $0["appearance"] == nil }?["value"] as? [String: String]
    let prefix = "extended-srgb:"
    guard let fill = base?["solid"], fill.hasPrefix(prefix),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw RenderError("Expected a solid sRGB background in the Icon Composer file.") }

    let components = fill.dropFirst(prefix.count).split(separator: ",").compactMap { Double($0).map { CGFloat($0) } }
    guard components.count == 4, let color = CGColor(colorSpace: colorSpace, components: components)
    else { throw RenderError("Invalid Icon Composer background color.") }
    return color
}

func generate(check: Bool) throws {
    let scratch = files.temporaryDirectory.appending(path: UUID().uuidString)
    try files.createDirectory(at: scratch, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: scratch) }

    // Tighter viewBoxes preserve the source geometry and give each template its platform padding.
    // All are centered on the mark's optical center at (510, 497) in the source.
    let menu = try monochromeSVG(width: "20", height: "18", viewBox: "150 173 720 648")
    let action = scratch.appending(path: "action.svg")
    try monochromeSVG(width: "1024", height: "1024", viewBox: "96 83 828 828").write(to: action)
    let actionPNG = scratch.appending(path: "action.png")
    try swiftDraw(action, format: "png", output: actionPNG)

    let control = scratch.appending(path: "control.svg")
    try monochromeSVG(width: "24", height: "24", viewBox: "142 129 736 736").write(to: control)
    let symbol = scratch.appending(path: "mindrop.mark.svg")
    try swiftDraw(control, format: "sfsymbol", output: symbol, options: ["--insets", "3,0.5,3,0.5"])

    let markPNG = scratch.appending(path: "mark.png")
    try swiftDraw(artwork, format: "png", output: markPNG)
    guard let source = CGImageSourceCreateWithURL(markPNG as CFURL, nil),
          let mark = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw RenderError("Could not read the rasterized Icon Composer artwork.") }
    let background = try backgroundColor()
    let fallback = try opaquePNG(mark: mark, background: background, size: 1024)

    let outputs: [(String, Data)] = [
        ("\(assetCatalog)/MindropMenuBarMark.imageset/MindropMenuBarMark.svg", menu),
        ("MindropControls/Assets.xcassets/mindrop.mark.symbolset/mindrop.mark.svg", try Data(contentsOf: symbol)),
        ("MindropAction/Resources/Assets.xcassets/\(appIcon)", try Data(contentsOf: actionPNG)),
        ("\(assetCatalog)/\(appIcon)", fallback),
        ("MindropWatch/Assets.xcassets/\(appIcon)", fallback),
        ("docs/assets/app-icon.png", try opaquePNG(mark: mark, background: background, size: 256)),
    ]
    var outdated: [String] = []
    for (path, data) in outputs {
        let output = repository.appending(path: path)
        guard (try? Data(contentsOf: output)) != data else { continue }
        if check {
            outdated.append(path)
        } else {
            try data.write(to: output, options: .atomic)
            print("Updated \(path)")
        }
    }
    if !outdated.isEmpty {
        throw RenderError("Regenerate the Mindrop mark assets:\n" + outdated.joined(separator: "\n"))
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty || arguments == ["--check"] else {
        throw RenderError("Usage: swift Tools/RenderAppIcon.swift [--check]")
    }
    try generate(check: arguments == ["--check"])
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
