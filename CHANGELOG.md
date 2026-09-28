# Changelog

All notable changes to CleanCut. Versions follow the milestone plan in [docs/SPEC.md](docs/SPEC.md).

## [Unreleased]
### Fixed
- After choosing a photo from Photos (or taking one with the camera), the editor no longer spreads under the status bar and home indicator, where the Close/Export buttons and the tool tabs couldn't be tapped. The editor was presented while the picker was still animating away, which left it with no safe-area insets; it now waits for that dismissal to finish.

## [0.9.0] — Polish & docs (M7)
### Added
- Pinch-to-zoom and pan on the studio canvas (re-renders at the magnified size), double-tap to fit, and a zoom badge.
- `cleancut-bench preview`: preview frame times at 1206² (worst case 4.2 ms p50 on M4 Max).
- A demo recording pipeline: a paced UI flow, `simctl` recording, and a dependency-free MP4→GIF script (`make demo`).
- README, ARCHITECTURE (mermaid), DECISIONS 007–008, and the preview section in BENCHMARKS.

### Changed
- Export cards stack the pixel size and file type so they fit at large Dynamic Type sizes.
- Checked the layout in light and dark mode, at XXL text, and on iPad (inspector layout).

## [0.7.0] — Core ML benchmark (M6)
### Added
- `Tools/ModelConversion`: a reproducible conversion of U²-Netp and ISNet (Apache-2.0) to Core ML, with pinned dependencies, strict weight loading, a PyTorch parity check, SHA-256 in `Models/manifest.json`, and a 6-bit palettized ISNet variant.
- `CoreMLSegmenter`: a Float16 grayscale-image output wrapped straight into a `CIImage`, per-stage timings, and the model isolated in an actor.
- `SegmentationBenchmark` and `cleancut-bench segment`: every engine × compute unit, measuring load, reload, first run, p50/p90, end-to-end, IoU vs Vision and peak memory. See [docs/BENCHMARKS.md](docs/BENCHMARKS.md).
- The app bundles U²-Netp: it's a Settings option and the automatic fallback where Vision can't run (the Simulator), through `FallbackSegmenter`.
- `THIRD_PARTY_NOTICES.md` and an Acknowledgements screen.

## [0.6.0] — Batch mode (M5)
### Added
- `BatchProcessor`: a sliding-window task group (bounded concurrency) with ImageIO downsampling at decode, an `AsyncStream` of progress events, cancellation, and per-photo failure isolation.
- Batch UI: pick up to 50 photos, apply your last style, choose formats, and watch a live progress grid. Cancel, retry failed photos, save all, or share.
- `MemoryProbe` / `PeakMemorySampler` (`phys_footprint`), plus the `cleancut-bench batch` and `memprobe` commands.
- [Batch memory report](docs/benchmarks/batch-memory.md).

### Changed
- Each batch photo and each editor session renders through its own short-lived `CIContext`. A long-lived context accumulated ~1.5 GB across photos, and nothing released it except dropping the context (see DECISIONS 006). Batch peak memory went from ~2.9 GB to ~0.86 GB.

## [0.5.0] — Editor (milestones M1–M4)
### Added
- **Segmentation:** Vision foreground *instance* masks (iOS 18 Swift API) behind a `Segmenter` protocol. There's a low-res `LabelMap` for tap-to-select with near-miss snapping, and a `MaskSegmenter` for precomputed masks (Simulator, tests).
- **Pure pipeline:** `Pipeline.makeImage(inputs, recipe, outputSize)` renders in output space: framing, feathering, edge decontamination, drop and contact shadows, backgrounds (solid, studio sweep, transparent).
- **Custom Metal CIKernel:** `decontaminateEdges` solves the compositing equation to remove backdrop color from soft edges.
- **Editor:** a live `MTKView` preview through a Metal-backed `CIContext` (on demand, with a display link only while animating), a format segmented control, Select / Background / Shadow / Edges tools, undo/redo, press-and-hold compare, the "lift" reveal, an edge-of-frame tip, and an iPad/Mac inspector layout.
- **Export:** full-quality render from the working image, JPEG/PNG in sRGB, Save to Photos (add-only), and Share.
- **Tooling:** the `cleancut-bench render|sample` CLI, UI flow test with screenshot export (`make screenshots`), Vision integration tests on macOS.

### Fixed
- Combining instance masks with additive compositing doubled alpha, which halved coverage (a see-through cutout). Masks are now combined with a per-pixel maximum.
- Lanczos resampling clamps at the image border, so a product touching the photo's edge smeared across the canvas. Transformed images are now cropped to their own extent.

## [0.1.0] — Foundation
### Added
- XcodeGen project: iOS app, multiplatform `CleanCutKit` framework, test bundle, macOS `cleancut-bench` CLI.
- `Recipe` value model (background, shadow, edges, export preset) with clamping and `Codable` support.
- Marketplace export presets (Depop, Vinted, Amazon, Cutout) and pure framing geometry.
- Undo/redo `History`.
- Design tokens and base components (buttons, chips, sliders); app icon rendered from source.
- GitHub Actions CI (macOS tests + iOS Simulator build), Makefile.
