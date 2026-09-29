# Decisions

Short architecture decision records: what was decided, why, and what it costs.

## 001 — XcodeGen, not a checked-in `.xcodeproj`
**Decision.** `project.yml` is the source of truth. `CleanCut.xcodeproj` is generated and git-ignored.
**Why.** Diffs you can review and no `.pbxproj` merge conflicts. The special Metal build flags that Core Image kernels need are declared once, in plain text.
**Cost.** Contributors run `brew install xcodegen && make generate` once.

## 002 — The image pipeline is a separate, multiplatform framework
**Decision.** `CleanCutKit` holds all imaging, segmentation, batch and benchmark code. It builds for iOS and macOS and has no UIKit/SwiftUI dependency. The app is a thin SwiftUI layer on top.
**Why.** Tests run natively on a Mac in seconds, with real Vision and GPU, and no Simulator. The benchmark CLI reuses exactly the code the app ships. The framework can't reach for UI state, which keeps the boundary honest.
**Cost.** One more target, plus `public` annotations on the API.

## 003 — A Recipe is a value, and every length in it is relative
**Decision.** `Recipe` is a `Codable & Hashable & Sendable` struct. Shadow distance, blur and feather are stored as fractions of the subject's short side, never in pixels.
**Why.** (1) Undo/redo is a stack of values ([`History`](../Kit/CleanCutKit/Recipe/History.swift)). (2) Batch mode applies one recipe to 50 photos of different sizes. (3) A 320 px preview and a 1280 px export look the same: `previewAndExportLookTheSame` checks it at PSNR > 32 dB.
**Cost.** Every stage has to convert relative units to pixels, in one place.

## 004 — Render in output space
**Decision.** The pipeline first maps the source and mask into the output canvas (crop + downscale), then runs blurs, the edge kernel and compositing at output resolution.
**Why.** A 48 MP photo exported at 2000 px never blurs 48 MP of pixels, so preview and export cost scale with the output size, not the camera sensor. Core Image only evaluates the region of interest, so the crop is effectively free.
**Cost.** Parameters must be relative (see 003). Framing has to be computed before compositing.

## 005 — Main-actor-by-default app, non-isolated kit
**Decision.** The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The kit keeps the default (non-isolated) and exposes `Sendable` values and services.
**Why.** UI code is main-actor code, so the annotation noise goes away. Imaging work is off the main actor by construction. Swift 6's checks enforce the boundary at compile time.

## 006 — A short-lived `CIContext` per photo, not one for the whole app
**Decision.** Batch mode creates a `CIContext` for each photo, and each editor session owns its own. The usual advice is "create one context and reuse it". That's right for re-rendering the same image (the live preview) and wrong across many unrelated photos.
**Why.** Measured with `cleancut-bench batch` / `memprobe` on 12 MP photos (M4 Max, macOS 26). A long-lived Metal-backed context grew by 200–300 MB per photo and levelled off around 1.5 GB. `clearCaches()`, `cacheIntermediates: false` and `.memoryTarget` all left it unchanged. With a context per photo, the footprint between photos stays flat at 400–600 MB (≈ 200 MB of which is Vision's model), and batch peak memory fell from ~2.9 GB to ~0.86 GB at the same speed.
**Cost.** Creating a context per photo costs a few milliseconds, against ~130 ms of work per photo.

## 007 — Vision by default, U²-Netp as the fallback
**Decision.** Vision's foreground instance mask is the default engine. A bundled 2.4 MB U²-Netp Core ML model takes over only when Vision reports it *can't run here* (`FallbackSegmenter`). Real failures such as "no product found" are shown to the user and never masked.
**Why.** Vision gives separate instances (tap-to-select), a mask guided to full resolution, and ships no weights. But its instance mask can't create an inference context in the iOS Simulator, and a demo that breaks on a reviewer's first run is a bad demo. U²-Netp runs everywhere and in 4.6 ms on the Neural Engine ([BENCHMARKS](BENCHMARKS.md)).
**Cost.** U²-Netp returns one mask for everything salient, so tap-to-select only works because that mask is split into separate objects (ADR 009); objects that touch stay one. The model upsamples a 320² mask, so its edges are softer than Vision's.

## 008 — Pin Core ML compute units
**Decision.** The app runs U²-Netp with `.cpuAndNeuralEngine`, not `.all`.
**Why.** Measured: `.all` was slower than either CPU+GPU or CPU+ANE for every model tested (U²-Netp 7.5 vs 4.6 ms, ISNet 38 vs 24 ms), probably because the graph gets split across devices.
**Cost.** Re-measure on each chip generation. On an iPhone SE (A13) the ordering holds: CPU+ANE 22.1 ms, `.all` 35.8 ms, and the GPU (95.5 ms) is slower than the CPU (67.2 ms) ([BENCHMARKS](BENCHMARKS.md#iphone-se-2nd-generation-a13-bionic)).

## 009 — Split a salient-object mask into its disconnected objects
**Decision.** `CoreMLSegmenter` splits U²-Netp's single mask into its 8-connected regions (`LabelMap.separatingObjects`), largest first. Each region becomes an instance you can tap. Its mask is the model's soft mask multiplied by a binary gate: the part of the image nearest that region (`nearestInstances`, sampled nearest-neighbour). Specks under 0.1% of the label map join the nearest object instead of becoming their own chip.
**Why.** Without it, a photo with two products gave one "Object 1" wherever Vision can't run, and tapping did nothing. The regions partition the image and meet in background, so selecting everything returns the model's mask unchanged. The per-object masks recombine into it under `CIMaximumCompositing`, so preview/export parity holds. A second model (true instance segmentation) would cost download size for a fallback path.
**Cost.** Touching or overlapping products stay one object: only Vision can separate them. Where two objects nearly touch, the seam between their gates cuts through soft edges at label-map resolution (~4 photo pixels at 2048 px). Post-processing gains ~0.9 ms for the split, plus ~1.9 ms for the partition when there are two or more objects (512×683 map, M4 Max, `-O`).

## 010 — Guided capture: heuristic checks on the GPU, a Core ML mask, a coach that never blocks
**Decision.** Guided capture scores each camera frame (at most 15 fps) with two custom Core Image kernels, reduced by `CIAreaAverage` and read back as eight floats in one render. The statistics are weighted by a U²-Netp subject mask, refreshed every third frame. `CaptureCoach` turns per-frame verdicts into one tip and changes a check only after its new state has held for 0.4 s. The shutter always works.
**Why.**
- *U²-Netp, not Vision, for the live mask.* It runs in the Simulator, so the replay camera exercises the real path, and it measured 7.8 ms end to end against 15 ms for Vision on the M4 Max ([BENCHMARKS](BENCHMARKS.md)). `liveMask` also skips the label map and object split that framing doesn't need. Framing only needs a coarse box; Vision still does the cutout in the editor.
- *Core Image kernels, not a Metal compute reduction.* The Kit compiles every `.metal` file as a CIKernel (001), and `CIAreaAverage` is already a GPU reduction. One 2×1 `RGBAf` readback per frame, plus a ≤128-px mask readback for the bounding box.
- *An analysis context without color management.* Sensors clip in encoded values, so thresholds like "a channel ≥ 0.98" only mean something there.
- *Normalized sharpness.* Laplacian energy divided by the subject's own luma variance, at a fixed 720-px short side. A raw Laplacian variance calls every plain product blurry and depends on the camera's resolution. On the test scenes, sharp frames score 0.4–3.5, a 2-px blur 0.02–0.14 and handheld motion blur about 0.001; the threshold is 0.1.
- *No centering check.* The editor reframes the product for every preset, so only "all of it in frame" and "big enough" reach the export.
- *Advise, never block.* A heuristic will sometimes be wrong about a real product (a glossy white bottle, a deliberately dark one). A disabled shutter would turn that into a dead end.
**Cost.** The thresholds are calibrated on generated scenes, not on real photos, and need tuning on a device (`CaptureThresholds` keeps them in one place). A white or chrome product can read as glare or overexposure. Auto-exposure hides a dim room by raising ISO, so "too dark" only fires when the frame itself is dim; noise isn't measured. On an iPhone SE (A13) the analysis costs 22.5 ms per frame on average (p90 44.9 ms on frames that refresh the mask) against the 66.7 ms budget, measured on replay frames by `CaptureBenchmark` ([BENCHMARKS](BENCHMARKS.md#iphone-se-2nd-generation-a13-bionic)). The AVFoundation code (permissions, rotation, interruptions) still needs testing on devices beyond that one; the frame-timing HUD shows the live analysis time per frame.
