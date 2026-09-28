# Changelog

All notable changes to CleanCut. Versions follow the milestone plan in [docs/SPEC.md](docs/SPEC.md).

## [0.1.0] — Foundation
### Added
- XcodeGen project: iOS app, multiplatform `CleanCutKit` framework, test bundle, macOS `cleancut-bench` CLI.
- `Recipe` value model (background, shadow, edges, export preset) with clamping and `Codable` support.
- Marketplace export presets (Depop, Vinted, Amazon, Cutout) and pure framing geometry.
- Undo/redo `History`.
- Design tokens and base components (buttons, chips, sliders); app icon rendered from source.
- GitHub Actions CI (macOS tests + iOS Simulator build), Makefile.
