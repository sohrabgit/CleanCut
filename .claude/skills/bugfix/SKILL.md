---
name: bugfix
description: Fix a bug in CleanCut test-first (reproduce with a failing test, find the root cause, fix, keep a regression test, changelog, PR into develop). Use when the user reports something broken, wrong output pixels, a crash, a memory or performance regression, or flaky behaviour.
---

# Bug-fix workflow

Read `CLAUDE.md` first. The **Hard-won gotchas** list covers the most likely culprits for image bugs.

## 1. Reproduce
- Get the exact symptom: the screen, the steps, the input photo, and expected vs actual. Ask the user for missing details only if you can't reproduce without them.
- Branch: `git checkout develop && git pull && git checkout -b fix/<short-slug>`.
- Reproduce with the cheapest tool that shows the bug:
  - Pipeline or pixels: `cleancut-bench render <photo> [--masks <dir>] [--preview]`, and inspect the output.
  - UI: `make screenshots`, then look at the PNGs.
  - Memory: `cleancut-bench memprobe <folder> --stage …` or `batch --trace`.
  - Performance: `cleancut-bench preview` or `segment`.

## 2. Write a failing test first
- Add a test that fails for the *reason* of the bug, not just its symptom. For image bugs, use a `SyntheticScene` shaped like the trigger. For example, the edge-smear bug needed a subject that touches the photo's edge.
- Name it after the behaviour, e.g. `productTouchingThePhotoEdgeDoesNotSmearOutward`. Add a `/// Regression:` doc comment saying what used to go wrong.
- Run it and confirm it fails (`xcodebuild test … -only-testing:CleanCutKitTests/<Suite>/<test>` or `make test`).
- If a unit test can't reproduce it (a device-only or UI-only bug), say so, and add the closest automated check you can: a UI test step, or a benchmark assertion.

## 3. Find the root cause
- Bisect by stage: turn pipeline stages on and off, compare paths (e.g. Vision vs `MaskSegmenter`, preview vs export), or measure per stage. Change one variable at a time.
- Check the known traps: color-managed masks, `transformed` without cropping, additive mask compositing, a long-lived `CIContext`, Core Image's bottom-left vs top-left origin, points vs pixels, Simulator-only Vision failures.
- Explain the cause in one or two sentences before fixing. If it's a new class of trap, plan to add it to the gotchas in `CLAUDE.md`.

## 4. Fix
- Make the smallest change that fixes the cause. Fix every call site with the same pattern (`grep` for it) rather than just the one you found.
- Don't weaken or delete existing tests to make things pass.
- Run `make test`, `make test-ios` and `make build`. Everything must pass, including the new test, which should now pass.
- Re-run the step-1 reproduction and confirm the symptom is gone. Look at the output or screenshots yourself.

## 5. Record it
- `CHANGELOG.md`: add an entry under `## [Unreleased]` → `### Fixed` describing the symptom and the cause in plain words.
- Add a gotcha line to `CLAUDE.md` if future sessions could fall into the same trap. Add an ADR in `docs/DECISIONS.md` if the fix changes a design decision. Regenerate `docs/BENCHMARKS.md` numbers if they moved.

## 6. Commit and PR
- Use the subject `Fix <symptom>`. The body gives the cause, the fix, and the regression test that guards it. End with the attribution line from the session's instructions.
- `git push -u origin fix/<slug>`, then `gh pr create --base develop`. Include the reproduction steps, the root cause, the fix, and a Test plan (the failing-then-passing test, the reproduction re-checked). Check CI with `gh pr checks`.
