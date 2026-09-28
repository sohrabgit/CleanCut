---
name: feature
description: Add a new feature or change to CleanCut end to end (spec, plan, branch, implement, test, verify UI, document, PR into develop). Use when the user asks to build, add, change or improve something in the app or the CleanCutKit pipeline.
---

# Feature workflow

Follow these steps in order. Read `CLAUDE.md` first, especially **Code rules** and **Hard-won gotchas**.

## 1. Understand and scope
- Restate the feature as a user story, e.g. "A reseller can …".
- Read the relevant parts of `docs/SPEC.md`, `docs/ARCHITECTURE.md` and `docs/DECISIONS.md`, and the code you'll touch.
- Decide where it belongs: anything testable goes in `Kit/CleanCutKit` (pure, non-isolated), and UI and state go in `App/`.
- If requirements are ambiguous, or there's a real product or UX choice, ask the user before building. Don't ask about things you can decide from the existing conventions.

## 2. Plan
Write a short plan in your reply (or in plan mode for big features):
- files to add or change (Kit / App / Tests / docs)
- new or changed public API, including `Recipe` fields (relative units only, a default, clamping)
- UI: which screen and tool, which `DesignSystem` components, accessibility (labels, Dynamic Type, Reduce Motion), empty and error states
- tests you'll add, and how you'll verify it visually
- the risks you know about

## 3. Branch
```sh
git checkout develop && git pull
git checkout -b feature/<short-slug>
```

## 4. Implement, in small steps
- Kit first, with tests alongside, then the App.
- `make test` after each meaningful step. The build treats warnings as errors under Swift 6 strict concurrency.
- Edit `project.yml` (then `make generate`) for new targets, resources or build settings. Never edit the generated `.xcodeproj`.
- Reuse existing pieces: `Pipeline`, `resampled(by:)`, `Matte.canonical`, `RenderService`, `Exporter`, `Tokens`, `Chip`, `LabeledSlider`, `FriendlyError`.

## 5. Test
- **Unit (Swift Testing)** in `Tests/CleanCutKitTests`: behaviour, edge cases, and pixel invariants on a `SyntheticScene` where it's visual. A new `Recipe` field needs a Codable round-trip and a clamping test.
- Gate GPU-only tests with `.enabled(if: TestEnvironment.hasMetal)`. Gate real-Vision tests off the Simulator.
- **UI:** if the flow changed, extend `UITests/EditorFlowTests.swift` with a step and a `snapshot(...)`.
- Run `make test`, `make test-ios` and `make build`. All must pass.

## 6. Verify for real
- For UI: run `make screenshots`, then **open and look at the PNGs** in `.build/screenshots`. Check light and dark mode (`xcrun simctl ui booted appearance light|dark`). For layout-sensitive changes, check large text (`xcrun simctl ui booted content_size extra-extra-large`, then reset to `large`) and iPad (`make screenshots SIM="iPad Air (5th generation)"`).
- For pipeline output: `make bench`, then `.build/dd/Build/Products/Release/cleancut-bench render <photo> --out .bench/render`, then look at the result.
- For performance-sensitive code: re-run `cleancut-bench preview` / `batch` / `segment` and compare with `docs/BENCHMARKS.md`.
- Report what you checked and what you couldn't. Don't claim results you didn't observe.

## 7. Document
- `CHANGELOG.md`: add an entry under `## [Unreleased]`, creating the heading if it's missing.
- `docs/SPEC.md` / `README.md` if user-facing. `docs/DECISIONS.md` if you made a non-obvious trade-off. `docs/BENCHMARKS.md` if numbers changed (regenerate them, don't hand-edit).
- New third-party code or models: verify the license and add to `THIRD_PARTY_NOTICES.md`.

## 8. Commit and PR
- Commit with an imperative subject and a *why* body. Split Kit and App commits when both are big. End each message with the attribution line from the session's instructions.
- `git push -u origin feature/<slug>`, then `gh pr create --base develop` with a Summary and a Test plan checklist (tests run, screenshots checked, what's still unverified, e.g. on-device).
- Check CI with `gh pr checks`. Don't merge into `master` or tag a release unless the user asks.
