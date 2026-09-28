# CleanCut: guide for Claude Code sessions

CleanCut is an on-device product-photo studio for iOS 18+: Vision/Core ML segmentation, a Core Image pipeline with a custom Metal kernel, studio compositing and marketplace export. It's a portfolio project for a Photoroom Senior iOS application. Code quality, a polished UI and honest docs all matter.

Read [README.md](README.md) for the overview. The deeper docs are [docs/SPEC.md](docs/SPEC.md) (product + UI/UX), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DECISIONS.md](docs/DECISIONS.md) (ADRs 001–010) and [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Workflows
- **New feature or change:** use the `/feature` skill.
- **Bug fix:** use the `/bugfix` skill. It starts with a failing test.
- **Release:** a PR from `develop` to `master`, then a `vX.Y.Z` tag, then CHANGELOG version headings.

## Branches, commits, PRs
- Branch off `develop`: `feature/<slug>`, `fix/<slug>`, `chore/<slug>`. Never commit straight to `master`.
- PRs target `develop` and need green CI. Only release PRs go from `develop` to `master`.
- Commit messages are imperative subjects, with a body explaining *why*. Split Kit and App changes into separate commits when both are large.
- Ask before outward-facing actions: making the repo public, creating releases, merging to `master`, deleting tags or branches.

## Commands
| | |
|---|---|
| `make generate` | Regenerate `CleanCut.xcodeproj` from `project.yml` (the project file is generated and git-ignored; **edit `project.yml`, never the pbxproj**) |
| `make test` | CleanCutKit tests, natively on macOS (~3 s). **Run before every commit.** |
| `make test-ios` | Same suite on the iOS Simulator |
| `make build` | Build the app for the Simulator |
| `make screenshots` | UI flow test and screenshots in `.build/screenshots`. **Look at them after any UI change.** |
| `make bench` | Build the `cleancut-bench` CLI: `render`, `sample`, `batch`, `segment`, `preview`, `memprobe` |
| `make demo` | Record `docs/media/demo.gif` from the Simulator |
| `make -C Tools/ModelConversion` | Convert U²-Netp/ISNet to Core ML (pinned Python env via `uv`) |

`Tools/scripts/xcfilter.sh` condenses xcodebuild output. With `set -o pipefail`, failures still fail.

## Layout
- `Kit/CleanCutKit/` is a **non-isolated, UI-free framework** (iOS + macOS): Recipe, Pipeline, Kernels (Metal), Capture, Segmentation, Rendering, Batch, Bench. Anything testable goes here.
- `App/` is SwiftUI, **`MainActor` by default** (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Use `@concurrent` for heavy async work (decoding, rendering).
- `Tests/CleanCutKitTests/` uses Swift Testing, with `Support/TestEnvironment.swift` (`SyntheticScene`, PSNR, bitmap helpers).
- `UITests/` holds XCTest UI flows: `EditorFlowTests` (screenshots) and `DemoRecordingTests` (GIF).

## Code rules
- **Swift 6, strict concurrency, warnings are errors.** Don't silence diagnostics with `@unchecked Sendable` or `nonisolated(unsafe)` unless you explain why in a comment. Non-`Sendable` framework objects go inside an actor (see `CoreMLSegmenter.Engine`).
- **The pipeline stays pure:** `Pipeline.makeImage(inputs, recipe:, outputSize:)` builds a lazy `CIImage`, with no side effects and no rendering. Preview, export, batch and tests all use it.
- **Every length in a `Recipe` is relative** (a fraction of the subject's short side). Never add pixel parameters, or preview/export parity breaks. `previewAndExportLookTheSame` guards this.
- **A new `Recipe` field** needs a default, clamping in `clamped()`, and a Codable round-trip test.
- Match the surrounding style: doc comments explain *why*, and names come from the domain (`Backdrop`, `ShadowSettings`, `unit`).
- UI uses `App/DesignSystem` tokens and components (`Tokens`, `Chip`, `LabeledSlider`, `.primary`/`.secondary` button styles). One accent color. 44-pt targets, VoiceOver labels, Dynamic Type, Reduce Motion. Error copy goes through `FriendlyError`, never raw errors.

## Hard-won gotchas (each cost a real bug; don't reintroduce)
1. **Masks are data, not color.** Create them with `options: [.colorSpace: NSNull()]` and render with `colorSpace: nil` (`RenderService.makeMaskImage`), so coverage values are never gamma-converted.
2. **Transform with `resampled(by:)`, not `transformed(by:highQualityDownsample:)` alone.** Lanczos clamps at the border, so a product touching the photo's edge smears across the canvas unless you crop to the transformed extent.
3. **Combine masks with `CIMaximumCompositing`, not addition.** Adding opaque masks gives alpha 2, which halves coverage when unpremultiplied (a see-through cutout).
4. **A long-lived `CIContext` accumulates GPU memory across photos** (~1.5 GB). `clearCaches()`, `cacheIntermediates` and `memoryTarget` don't fix it. Use a context per photo or editor session (DECISIONS 006).
5. **Vision's foreground instance mask can't run in the iOS Simulator.** `FallbackSegmenter` uses U²-Netp there, and samples use precomputed masks. Vision integration tests skip in the Simulator.
6. **SwiftUI already defines `BackgroundStyle` and `ShadowStyle`.** That's why the Kit types are `Backdrop` and `ShadowSettings`. Check new public Kit type names for clashes.
7. **Core ML:** pin compute units (`.all` measured slower). A model compiled to a new temporary path misses the OS's Neural Engine compile cache.
8. `CIContext.createCGImage` rejects single-channel output without a color space. Render the bytes yourself (see `makeMaskImage`).
9. **Don't present a full-screen cover while another presentation (the Photos picker, the camera) is still animating away.** It gets zero safe-area insets, so the editor's bars land under the status bar and home indicator. Await `waitForPresentationsToSettle()` in `HomeView` first. `EditorFlowTests.testEditorFromPhotoLibraryStaysInsideTheSafeArea` guards this. It skips unless the Simulator's library has a photo (`xcrun simctl addmedia booted <photo>`).
10. **An `.R8` `CIImage` reads as `(r, 0, 0, 1)`.** Multiplying a mask by it zeroes green and blue. Make gates and other multiplicative masks `.L8` (gray), as `LabelMap.gate` does.

## Assets and legal
- Never commit macOS system pictures or other third-party images. Local dev samples are named `App/Resources/Samples/local-*` and are git-ignored. Only the user's own photos become committed samples (`cleancut-bench sample <photo> --name <name>`).
- Never commit a `DEVELOPMENT_TEAM`. It lives in the git-ignored `Configs/Local.xcconfig`.
- Only U²-Netp (2.4 MB) is committed under `Models/`. ISNet packages are generated. New models need license verification and an entry in `THIRD_PARTY_NOTICES.md`.

## Docs to keep in sync
- `CHANGELOG.md`: an `Unreleased` section with Added / Changed / Fixed entries for every user-visible change.
- `docs/DECISIONS.md`: a new ADR for any non-obvious trade-off.
- `docs/BENCHMARKS.md`: regenerate the tables with `cleancut-bench` rather than hand-editing numbers, and state the hardware.
- `README.md` and `docs/SPEC.md` when a feature is user-facing. Claims must be measured (no "60 fps" without a number behind it).
