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
**Why.** (1) Undo/redo is a stack of values ([`History`](../Kit/CleanCutKit/Recipe/History.swift)). (2) Batch mode applies one recipe to 50 photos of different sizes. (3) The 1600 px preview and the 4000 px export look the same, and a parity test checks it.
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
**Cost.** U²-Netp finds one salient object, so tap-to-select degrades to a single object. The model upsamples a 320² mask, so its edges are softer than Vision's.

## 008 — Pin Core ML compute units
**Decision.** The app runs U²-Netp with `.cpuAndNeuralEngine`, not `.all`.
**Why.** Measured: `.all` was slower than either CPU+GPU or CPU+ANE for every model tested (U²-Netp 7.5 vs 4.6 ms, ISNet 38 vs 24 ms), probably because the graph gets split across devices.
**Cost.** Re-measure on each chip generation; the iPhone numbers may differ.
