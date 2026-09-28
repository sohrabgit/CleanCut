import CleanCutKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// cleancut-bench — command-line access to the CleanCut pipeline on macOS.
//
//   cleancut-bench render <photo> [--out <dir>] [--preset <id|all>]
//                                 [--background white|sweep|<hex>] [--shadow none|soft|contact|natural]
//                                 [--no-clean]

let usage = """
    usage:
      cleancut-bench sample <photo> --name <name> [--out App/Resources/Samples]
      cleancut-bench render <photo> [--out <dir>] [--preset depop|vinted|amazon|cutout|all]
                                    [--background white|sweep|RRGGBB] [--shadow none|soft|contact|natural] [--no-clean]
    """

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: ArraySlice<String>) {
        var iterator = raw.makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if key.hasPrefix("no-") {
                    flags.insert(key)
                } else if let value = iterator.next() {
                    options[key] = value
                }
            } else {
                positional.append(arg)
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func makeRecipe(_ args: Arguments) -> Recipe {
    var recipe = Recipe.default
    switch args.options["background"] ?? "white" {
    case "white": recipe.background = .solid(.white)
    case "sweep": recipe.background = .studioSweep(RGBA(hex: 0xF2EEE8))
    case let hex:
        guard let value = UInt32(hex, radix: 16) else { fail("bad background \(hex)") }
        recipe.background = .solid(RGBA(hex: value))
    }
    if let shadow = args.options["shadow"] {
        guard let kind = ShadowSettings.Kind(rawValue: shadow) else { fail("bad shadow \(shadow)") }
        recipe.shadow.kind = kind
    }
    recipe.edges.cleanEdges = !args.flags.contains("no-clean")
    return recipe
}

func render(_ args: Arguments) async throws {
    guard let path = args.positional.first else { fail(usage) }
    let outDir = URL(fileURLWithPath: args.options["out"] ?? ".bench/render", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let presets: [ExportPreset]
    switch args.options["preset"] ?? "all" {
    case "all": presets = ExportPreset.all
    case let id:
        guard let presetID = ExportPreset.ID(rawValue: id) else { fail("bad preset \(id)") }
        presets = [ExportPreset.preset(for: presetID)]
    }

    let renderer = RenderService()
    let clock = ContinuousClock()
    let image = try ImageLoader.load(url: URL(fileURLWithPath: path))
    let start = clock.now
    let segmenter: any Segmenter
    if let maskDir = args.options["masks"] {
        // Bundled-sample path: precomputed masks instead of live Vision.
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: maskDir), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        segmenter = MaskSegmenter(masks: urls.compactMap { CIImage(contentsOf: $0, options: [.colorSpace: NSNull()]) }, renderer: renderer)
    } else {
        segmenter = VisionSegmenter()
    }
    let photo = try await PreparedPhoto.prepare(image, segmenter: segmenter, renderer: renderer)
    if args.flags.contains("no-debug-proxy") == false, let inputs = photo.previewInputs(selection: nil) {
        let preview = Pipeline.makeImage(inputs, recipe: makeRecipe(args), outputSize: CGSize(width: 800, height: 800))
        if let cg = renderer.makeCGImage(preview) {
            try write(cg, to: outDir.appendingPathComponent("\(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)-preview.png"), type: .png)
        }
    }
    print("segmented \(image.width)×\(image.height) → \(photo.instances.count) instance(s) in \(clock.now - start)")

    let recipe = makeRecipe(args)
    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    for preset in presets {
        let exportStart = clock.now
        let data = try Exporter.export(photo, recipe: recipe, preset: preset, renderer: renderer)
        let url = outDir.appendingPathComponent("\(stem)-\(preset.id.rawValue).\(preset.fileType.fileExtension)")
        try data.write(to: url)
        print("  \(preset.name): \(url.path) (\(data.count / 1024) KB, \(clock.now - exportStart))")
    }
}

/// Writes a bundled sample: a downsized JPEG plus one mask PNG per instance,
/// precomputed with Vision so the Simulator can demo the full flow.
func sample(_ args: Arguments) async throws {
    guard let path = args.positional.first, let name = args.options["name"] else { fail(usage) }
    let outDir = URL(fileURLWithPath: args.options["out"] ?? "App/Resources/Samples", isDirectory: true)
    let maskDir = outDir.appendingPathComponent("\(name).masks", isDirectory: true)
    try? FileManager.default.removeItem(at: maskDir)
    try FileManager.default.createDirectory(at: maskDir, withIntermediateDirectories: true)

    let renderer = RenderService()
    let image = try ImageLoader.load(url: URL(fileURLWithPath: path), maxPixelSize: 2048)
    let result = try await VisionSegmenter().segment(image)

    try write(image, to: outDir.appendingPathComponent("\(name).jpg"), type: .jpeg, quality: 0.9)
    for instance in result.instances {
        guard let mask = renderer.makeMaskImage(try result.mask(for: [instance])) else { fail("mask render failed") }
        try write(mask, to: maskDir.appendingPathComponent("\(instance).png"), type: .png)
    }
    print("\(name): \(image.width)×\(image.height), \(result.instances.count) instance(s) → \(outDir.path)")
}

func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        fail("can't write \(url.path)")
    }
    let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path)") }
}

let args = Arguments(CommandLine.arguments.dropFirst(2))
switch CommandLine.arguments.dropFirst().first {
case "render": try await render(args)
case "sample": try await sample(args)
default: fail(usage)
}
