import CleanCutKit
import CoreImage
import CoreML
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

// cleancut-bench — command-line access to the CleanCut pipeline on macOS.
//
//   cleancut-bench render <photo> [--out <dir>] [--preset <id|all>]
//                                 [--background white|sweep|<hex>] [--shadow none|soft|contact|natural]
//                                 [--no-clean]

let usage = """
    usage:
      cleancut-bench sample <photo> --name <name> [--out App/Resources/Samples]
      cleancut-bench batch <folder> [--concurrency 1,2,4] [--presets depop,amazon] [--report <file.md>] [--trace]
      cleancut-bench segment <folder> [--models Models] [--count 12] [--runs 30] [--report docs/benchmarks/segmentation.md]
      cleancut-bench preview <photo> [--size 1206x1206] [--frames 120]
      cleancut-bench memprobe <folder> [--stage load|segment|mask|export] [--fresh-context] [--clear-caches] [--memory-target MB]
      cleancut-bench render <photo> [--out <dir>] [--preset depop|vinted|amazon|cutout|all]
                                    [--background white|sweep|RRGGBB] [--shadow none|soft|contact|natural] [--no-clean]
                                    [--masks <dir>] [--preview]
    """

struct Arguments {
    static let booleanFlags: Set<String> = ["fresh-context", "clear-caches", "trace", "preview"]
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: ArraySlice<String>) {
        var iterator = raw.makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if key.hasPrefix("no-") || Arguments.booleanFlags.contains(key) {
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
    if args.flags.contains("preview"), let inputs = photo.previewInputs(selection: nil) {
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

/// Runs batch mode over a folder of photos at several concurrency levels and
/// reports wall time and peak memory footprint.
func batch(_ args: Arguments) async throws {
    guard let folder = args.positional.first else { fail(usage) }
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !urls.isEmpty else { fail("no photos in \(folder)") }
    let levels = (args.options["concurrency"] ?? "1,2,4").split(separator: ",").compactMap { Int($0) }
    let presets = (args.options["presets"] ?? "depop,amazon").split(separator: ",").compactMap {
        ExportPreset.ID(rawValue: String($0)).map(ExportPreset.preset(for:))
    }

    let (width, height) = try photoSize(urls[0])
    var rows: [String] = []
    print("\(urls.count) photos (\(width)×\(height)), presets: \(presets.map(\.name).joined(separator: ", "))")
    for level in levels {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cleancut-batch-\(level)", isDirectory: true)
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let processor = BatchProcessor(segmenter: VisionSegmenter(), maxConcurrentJobs: level)
        let jobs = urls.map { url in BatchJob { size in try ImageLoader.load(url: url, maxPixelSize: size) } }
        let baseline = MemoryProbe.footprint()
        let sampler = PeakMemorySampler()
        sampler.start()
        let clock = ContinuousClock()
        let start = clock.now
        var finished = 0, failed = 0
        for await event in processor.process(jobs, recipe: .default, presets: presets, outputDirectory: output) {
            switch event {
            case .finished: finished += 1
            case .failed: failed += 1
            case .started: break
            }
            if args.flags.contains("trace"), case .started = event {} else if args.flags.contains("trace") {
                print("  after \(finished + failed): \(megabytes(MemoryProbe.footprint()))")
            }
        }
        let elapsed = (clock.now - start).seconds
        let peak = sampler.stop()
        let row = String(
            format: "| %d | %d | %.1f s | %.2f s | %@ | %@ |",
            level, finished, elapsed, elapsed / Double(max(finished, 1)),
            megabytes(peak), megabytes(peak > baseline ? peak - baseline : 0)
        )
        rows.append(row)
        print(row + (failed > 0 ? " (\(failed) failed)" : ""))
    }

    if let report = args.options["report"] {
        let markdown = """
            | Concurrency | Photos | Wall time | Per photo | Peak footprint | Above baseline |
            |---|---|---|---|---|---|
            \(rows.joined(separator: "\n"))

            \(urls.count) photos at \(width)×\(height), decoded to ≤ 3072 px, exported as \(presets.map(\.name).joined(separator: " + ")). \(BenchmarkMachine.description).

            """
        try markdown.write(toFile: report, atomically: true, encoding: .utf8)
        print("wrote \(report)")
    }
}

/// Diagnostic behind docs/DECISIONS.md 006: prints the memory footprint after
/// each photo while running progressively more of the pipeline.
///
///   --stage load|segment|mask|export   how far to run (default export)
///   --fresh-context                    new CIContext per photo
///   --clear-caches                     clearCaches() after each photo
///   --memory-target <MB>               CIContextOption.memoryTarget
func memprobe(_ args: Arguments) async throws {
    guard let folder = args.positional.first else { fail(usage) }
    let count = Int(args.options["count"] ?? "12") ?? 12
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.path < $1.path }
        .prefix(count)
    let stage = args.options["stage"] ?? "export"
    let target = args.options["memory-target"].flatMap { Int($0) }
    let shared = RenderService(cacheIntermediates: false, memoryLimitMB: target)
    print("stage \(stage), start \(megabytes(MemoryProbe.footprint()))")

    for (index, url) in urls.enumerated() {
        let image = try ImageLoader.load(url: url, maxPixelSize: 3072)
        if stage != "load", let result = try? await VisionSegmenter().segment(image) {
            let renderer = args.flags.contains("fresh-context") ? RenderService(cacheIntermediates: false, memoryLimitMB: target) : shared
            try autoreleasepool {
                let mask = try result.mask(for: nil)
                switch stage {
                case "mask":
                    _ = renderer.makeMaskImage(mask)
                case "export":
                    guard let bounds = result.subjectBounds(for: nil) else { return }
                    let inputs = PipelineInputs(source: CIImage(cgImage: image), mask: mask, subjectBounds: bounds)
                    _ = try Exporter.export(inputs, recipe: .default, preset: .amazon, renderer: renderer)
                default:
                    break
                }
            }
            if args.flags.contains("clear-caches") { renderer.context.clearCaches() }
        }
        print("  after \(index + 1): \(megabytes(MemoryProbe.footprint()))")
    }
}

/// Benchmarks Vision against the converted Core ML models across compute units.
func segmentBenchmark(_ args: Arguments) async throws {
    guard let folder = args.positional.first else { fail(usage) }
    let count = Int(args.options["count"] ?? "12") ?? 12
    let runs = Int(args.options["runs"] ?? "30") ?? 30
    let modelsDir = URL(fileURLWithPath: args.options["models"] ?? "Models", isDirectory: true)
    let renderer = RenderService()

    // Photos Vision finds a product in, decoded like the editor does for preview work.
    var images: [CGImage] = []
    var reference: [LabelMap] = []
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for url in urls where images.count < count {
        let image = try ImageLoader.load(url: url, maxPixelSize: 2048)
        guard let result = try? await VisionSegmenter().segment(image) else { continue }
        images.append(image)
        reference.append(result.labelMap)
    }
    print("\(images.count) photos with a detectable product")
    let benchmark = SegmentationBenchmark(images: images, measuredRuns: runs)

    var configurations = BenchmarkConfiguration.vision

    struct ManifestEntry: Decodable { let name: String; let package: String; let sizeMB: Double }
    let manifestURL = modelsDir.appendingPathComponent("manifest.json")
    let manifest = (try? JSONDecoder().decode([String: ManifestEntry].self, from: Data(contentsOf: manifestURL))) ?? [:]
    for entry in manifest.values.sorted(by: { $0.sizeMB < $1.sizeMB }) {
        let package = modelsDir.appendingPathComponent(entry.package)
        guard FileManager.default.fileExists(atPath: package.path) else {
            print("skipping \(entry.name): \(package.path) not found (run make -C Tools/ModelConversion)")
            continue
        }
        // Compile once to a stable location, as an app bundle would ship it: the
        // OS caches Neural Engine compilation per model location.
        let compiled = URL(fileURLWithPath: ".bench/compiled/\(entry.name).mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let clock = ContinuousClock()
            let start = clock.now
            let temporary = try await CoreMLSegmenter.compile(package)
            try FileManager.default.createDirectory(at: compiled.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporary, to: compiled)
            print("compiled \(entry.name) in \(Int((clock.now - start).milliseconds)) ms")
        }
        configurations += BenchmarkConfiguration.coreML(compiledModelAt: compiled, name: entry.name, sizeMB: entry.sizeMB, renderer: renderer)
    }

    var results: [BenchmarkResult] = []
    for configuration in configurations {
        let result = await benchmark.run(configuration, reference: configuration.isReference ? nil : reference)
        results.append(result)
        let status = result.error.map { "error: \($0)" }
            ?? String(format: "load %.0f ms, p50 %.1f ms, e2e %.1f ms, IoU %@", result.loadMS, result.inferenceP50MS, result.endToEndP50MS,
                      result.meanIoUVsVision.map { String(format: "%.3f", $0) } ?? "ref")
        print("\(configuration.engine) [\(configuration.compute)]: \(status)")
    }

    let markdown = BenchmarkReport.markdown(results, imageCount: images.count, machine: BenchmarkMachine.description)
    print("\n" + markdown)
    if let report = args.options["report"] {
        try markdown.write(toFile: report, atomically: true, encoding: .utf8)
        try BenchmarkReport.csv(results).write(toFile: report.replacingOccurrences(of: ".md", with: ".csv"), atomically: true, encoding: .utf8)
        print("wrote \(report)")
    }
}

/// Times live-preview frames the way the editor renders them: proxy inputs,
/// shared GPU context, rendering into a Metal texture the size of a drawable.
/// Each scenario changes one recipe parameter per frame, like a slider drag.
func previewBenchmark(_ args: Arguments) async throws {
    guard let path = args.positional.first else { fail(usage) }
    let dims = (args.options["size"] ?? "1206x1206").split(separator: "x").compactMap { Int($0) }
    guard dims.count == 2 else { fail("bad --size") }
    let frames = Int(args.options["frames"] ?? "120") ?? 120
    let renderer = RenderService()
    guard renderer.device != nil else { fail("needs a Metal GPU") }

    let image = try ImageLoader.load(url: URL(fileURLWithPath: path))
    let photo = try await PreparedPhoto.prepare(image, segmenter: VisionSegmenter(), renderer: renderer)
    guard let inputs = photo.previewInputs(selection: nil) else { fail("no subject") }

    let size = CGSize(width: dims[0], height: dims[1])
    let benchmark = PreviewBenchmark(inputs: inputs, size: size, frames: frames)

    print("\(image.width)×\(image.height) photo, proxy \(Int(inputs.source.extent.width))×\(Int(inputs.source.extent.height)), frames \(dims[0])×\(dims[1])")
    var rows: [PreviewBenchmark.Row] = []
    for scenario in PreviewBenchmark.scenarios {
        let row = try await benchmark.run(scenario, renderer: renderer)
        rows.append(row)
        print(String(format: "%@: GPU p50 %.2f ms, frame p50 %.2f ms, p90 %.2f ms", row.scenario, row.gpuP50MS, row.frameP50MS, row.frameP90MS))
    }
    if let report = args.options["report"] {
        let markdown = PreviewBenchmark.markdown(rows) + "\n\(frames) frames per scenario at \(dims[0])×\(dims[1]) (iPhone 17 Pro width @3×), after 10 warm-up frames. \(BenchmarkMachine.description).\n"
        try markdown.write(toFile: report, atomically: true, encoding: .utf8)
    }
}

func photoSize(_ url: URL) throws -> (Int, Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { fail("can't read \(url.path)") }
    return (width, height)
}

func megabytes(_ bytes: UInt64) -> String {
    String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

let args = Arguments(CommandLine.arguments.dropFirst(2))
switch CommandLine.arguments.dropFirst().first {
case "render": try await render(args)
case "sample": try await sample(args)
case "batch": try await batch(args)
case "memprobe": try await memprobe(args)
case "segment": try await segmentBenchmark(args)
case "preview": try await previewBenchmark(args)
default: fail(usage)
}
