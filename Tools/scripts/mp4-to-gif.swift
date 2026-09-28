#!/usr/bin/env swift
// Converts a screen recording to an optimized animated GIF with AVFoundation and
// ImageIO only — no ffmpeg/gifski needed.
//
//   swift Tools/scripts/mp4-to-gif.swift in.mp4 out.gif [--width 360] [--fps 12] [--start 0] [--end 999]

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: mp4-to-gif.swift in.mp4 out.gif [--width 360] [--fps 12] [--start s] [--end s]")
    exit(1)
}
let input = URL(fileURLWithPath: args.removeFirst())
let output = URL(fileURLWithPath: args.removeFirst())
func option(_ name: String, _ fallback: Double) -> Double {
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count, let value = Double(args[index + 1]) else { return fallback }
    return value
}
let width = option("width", 360)
let fps = option("fps", 12)

let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) var duration = 0.0
Task {
    duration = (try? await asset.load(.duration).seconds) ?? 0
    semaphore.signal()
}
semaphore.wait()
let start = option("start", 0)
let end = min(option("end", duration), duration)

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: width, height: 10_000)

let frameCount = Int((end - start) * fps)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    fatalError("can't create \(output.path)")
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)
let frameProperties = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps],
] as CFDictionary

for index in 0..<frameCount {
    let time = CMTime(seconds: start + Double(index) / fps, preferredTimescale: 600)
    if let frame = try? generator.copyCGImage(at: time, actualTime: nil) {
        CGImageDestinationAddImage(destination, frame, frameProperties)
    }
}
guard CGImageDestinationFinalize(destination) else { fatalError("GIF encoding failed") }
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("wrote \(output.path): \(frameCount) frames, \(size / 1024) KB")
