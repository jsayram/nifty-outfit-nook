#!/usr/bin/env swift
// Builds the bundled sample wardrobe images (Tests/NookTestSupport/SampleWardrobe) from the folder of
// generated originals, and measures each cutout's quality signals into manifest.json.
//
//   swift scripts/build-sample-wardrobe.swift <originals folder>
//
// The originals folder holds nook_b1 and nook_b2 (garment photos), nook_b2_cutouts (transparent
// PNGs), nook_b3 (person-c.jpg) and nook_b4_tryon (look-*.jpg). The images are AI-generated test
// data; see Tests/NookTestSupport/SampleWardrobe/README.md. Run it again only when the originals
// change: it rewrites every file in photos/, cutouts/, people/ and tryon/.
//
// - Photos: JPEG, 1024 px on the long side at most, quality 0.65.
// - Cutouts: cropped to the garment as the real cutout step does, 640 px at most, JPEG 2000 with
//   alpha, which ImageIO decodes in software. (PNG was 16 MB for the set. HEIC with alpha was
//   smaller still, but the simulator's HEVC decoder hung on it and froze the UI tests.)
// - Person and try-on previews: JPEG, 1280 px at most, quality 0.65.
// - Four items with no app category (bra set, pajamas, swimsuit, sports set) are left out.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let skipped: Set<String> = ["x-bra-set", "x-pajamas", "x-swimsuit", "x-sports-set"]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: build-sample-wardrobe.swift <originals folder>\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Packages/NookKit/Tests/NookTestSupport/SampleWardrobe")
let fileManager = FileManager.default

func load(_ url: URL) -> CGImage {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else { fatalError("Can't read \(url.path)") }
    return image
}

func rgba(_ image: CGImage, width: Int, height: Int, crop: CGRect? = nil) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let part = crop ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
    // Draw so that `part` fills the context.
    let scaleX = CGFloat(width) / part.width
    let scaleY = CGFloat(height) / part.height
    let flippedY = CGFloat(image.height) - part.maxY
    context.draw(
        image,
        in: CGRect(
            x: -part.minX * scaleX, y: -flippedY * scaleY, width: CGFloat(image.width) * scaleX,
            height: CGFloat(image.height) * scaleY))
    return context.makeImage()!
}

func fit(_ width: Int, _ height: Int, longSide: Int) -> (Int, Int) {
    let scale = min(1, Double(longSide) / Double(max(width, height)))
    return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) {
    try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    else { fatalError("Can't write \(url.path)") }
    CGImageDestinationAddImage(
        destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Can't finish \(url.path)") }
}

func jpeg(_ from: URL, to: URL, longSide: Int) {
    let image = load(from)
    let (width, height) = fit(image.width, image.height, longSide: longSide)
    // JPEG has no alpha, so draw onto an opaque context.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    write(context.makeImage()!, to: to, type: .jpeg, quality: 0.65)
}

struct Signals: Codable {
    var instanceCount: Int
    var coverage: Double
    var largestInstanceShare: Double
    var touchedEdges: Int
    var softEdgeRatio: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// The bundled cutout's size, after cropping and shrinking. Its shape sizes shoes in a look
    /// bundle (`GarmentCutout.aspectRatio`).
    var pixelWidth = 0
    var pixelHeight = 0
}

/// The cutout's alpha at full size, its signals, and the garment's bounds in pixels.
func measure(_ image: CGImage) -> (signals: Signals, bounds: CGRect) {
    let width = image.width
    let height = image.height
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let alpha = context.data!.bindMemory(to: UInt8.self, capacity: width * height)
    var solid = 0
    var visible = 0
    var soft = 0
    var minX = width
    var maxX = -1
    var minY = height
    var maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let value = alpha[y * width + x]
            if value >= 16 {
                visible += 1
                if value < 240 { soft += 1 }
            }
            if value > 127 {
                solid += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }
    precondition(solid > 0, "empty cutout")
    var edges = 0
    if minY <= 1 { edges |= 1 }
    if maxY >= height - 2 { edges |= 2 }
    if minX <= 1 { edges |= 4 }
    if maxX >= width - 2 { edges |= 8 }

    // Separate subjects: 8 px cells, joined across gaps of up to 3 cells, so a pair of shoes or
    // earrings counts as one piece, as it would to a person.
    let cell = 8
    let columns = (width + cell - 1) / cell
    let rows = (height + cell - 1) / cell
    var counts = [Int](repeating: 0, count: columns * rows)
    for y in 0..<height {
        for x in 0..<width where alpha[y * width + x] > 127 {
            counts[(y / cell) * columns + x / cell] += 1
        }
    }
    let on = counts.map { $0 >= 4 }
    var dilated = [Bool](repeating: false, count: on.count)
    let reach = 3
    for row in 0..<rows {
        for column in 0..<columns where on[row * columns + column] {
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let r = row + dy
                    let c = column + dx
                    if r >= 0, r < rows, c >= 0, c < columns { dilated[r * columns + c] = true }
                }
            }
        }
    }
    var label = [Int](repeating: -1, count: on.count)
    var areas: [Int] = []
    for start in 0..<dilated.count where dilated[start] && label[start] < 0 {
        var stack = [start]
        label[start] = areas.count
        var area = 0
        while let index = stack.popLast() {
            if on[index] { area += counts[index] }
            let row = index / columns
            let column = index % columns
            for (r, c) in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
            where r >= 0 && r < rows && c >= 0 && c < columns {
                let next = r * columns + c
                if dilated[next] && label[next] < 0 {
                    label[next] = areas.count
                    stack.append(next)
                }
            }
        }
        areas.append(area)
    }
    let total = areas.reduce(0, +)
    let real = areas.filter { Double($0) >= Double(total) * 0.02 }
    let signals = Signals(
        instanceCount: max(1, real.count),
        coverage: Double(solid) / Double(width * height),
        largestInstanceShare: Double(real.max() ?? total) / Double(max(1, real.reduce(0, +))),
        touchedEdges: edges,
        softEdgeRatio: Double(soft) / Double(max(1, visible)),
        x: Double(minX) / Double(width),
        y: Double(minY) / Double(height),
        width: Double(maxX - minX + 1) / Double(width),
        height: Double(maxY - minY + 1) / Double(height))
    return (signals, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

func stems(_ folder: String, ext: String) -> [String] {
    let url = source.appendingPathComponent(folder)
    let names = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
    return names.filter { $0.hasSuffix("." + ext) }.map { String($0.dropLast(ext.count + 1)) }.sorted()
}

for folder in ["photos", "cutouts", "people", "tryon"] {
    try? fileManager.removeItem(at: root.appendingPathComponent(folder))
}

var manifest: [String: Signals] = [:]
let garmentStems = (stems("nook_b1", ext: "jpg").filter { $0.hasPrefix("g-") }
    + stems("nook_b2", ext: "jpg")).filter { !skipped.contains($0) }
for stem in garmentStems {
    let photoSource =
        fileManager.fileExists(atPath: source.appendingPathComponent("nook_b1/\(stem).jpg").path)
        ? "nook_b1" : "nook_b2"
    jpeg(
        source.appendingPathComponent("\(photoSource)/\(stem).jpg"),
        to: root.appendingPathComponent("photos/\(stem).jpg"), longSide: 1024)

    let cutout = load(source.appendingPathComponent("nook_b2_cutouts/\(stem).png"))
    let (measured, bounds) = measure(cutout)
    var signals = measured
    // Crop to the garment with a margin of about 1%, then shrink.
    let margin = CGFloat(max(cutout.width, cutout.height)) * 0.01
    let crop = bounds.insetBy(dx: -margin, dy: -margin)
        .intersection(CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height)).integral
    let (width, height) = fit(Int(crop.width), Int(crop.height), longSide: 640)
    signals.pixelWidth = width
    signals.pixelHeight = height
    manifest[stem] = signals
    write(
        rgba(cutout, width: width, height: height, crop: crop),
        to: root.appendingPathComponent("cutouts/\(stem).jp2"), type: UTType("public.jpeg-2000")!, quality: 0.75)
}

jpeg(
    source.appendingPathComponent("nook_b3/person-c.jpg"), to: root.appendingPathComponent("people/person.jpg"),
    longSide: 1280)
// The cool-weather preview showed a sleeveless vest, not the trench, in another room, so it's left out.
for stem in stems("nook_b4_tryon", ext: "jpg") where stem.hasPrefix("look-") && stem != "look-cool-weather" {
    jpeg(
        source.appendingPathComponent("nook_b4_tryon/\(stem).jpg"),
        to: root.appendingPathComponent("tryon/\(stem.dropFirst(5)).jpg"), longSide: 1280)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
print("Wrote \(garmentStems.count) garments, 1 person and the try-on previews to \(root.path)")
