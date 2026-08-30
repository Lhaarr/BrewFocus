import AppKit
import Foundation

private struct IconVariant {
    let filename: String
    let pixels: Int
}

private let variants = [
    IconVariant(filename: "brewfocus_16.png", pixels: 16),
    IconVariant(filename: "brewfocus_16@2x.png", pixels: 32),
    IconVariant(filename: "brewfocus_32.png", pixels: 32),
    IconVariant(filename: "brewfocus_32@2x.png", pixels: 64),
    IconVariant(filename: "brewfocus_128.png", pixels: 128),
    IconVariant(filename: "brewfocus_128@2x.png", pixels: 256),
    IconVariant(filename: "brewfocus_256.png", pixels: 256),
    IconVariant(filename: "brewfocus_256@2x.png", pixels: 512),
    IconVariant(filename: "brewfocus_512.png", pixels: 512),
    IconVariant(filename: "brewfocus_512@2x.png", pixels: 1024),
]

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift generate-macos-app-icon.swift <source.png> <master.png> <appiconset>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let masterURL = URL(fileURLWithPath: CommandLine.arguments[2])
let appIconSetURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read source icon at \(sourceURL.path)\n", stderr)
    exit(1)
}

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high
    graphicsContext.cgContext.setAllowsAntialiasing(true)
    graphicsContext.cgContext.setShouldAntialias(true)

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    canvas.fill()

    // The iPhone source is intentionally a full square. The legacy macOS asset
    // needs transparent corners so the system does not shrink that square onto
    // a second icon plate. Keep the art flat and let macOS provide its own edge.
    let cornerRadius = CGFloat(pixels) * 0.2237
    NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
    source.draw(
        in: canvas,
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

try FileManager.default.createDirectory(
    at: masterURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let master = try renderIcon(pixels: 1024)
try master.write(to: masterURL, options: .atomic)

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: appIconSetURL.appendingPathComponent(variant.filename), options: .atomic)
}

print("Generated macOS app icon from \(sourceURL.lastPathComponent)")
