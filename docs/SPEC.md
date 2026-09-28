# CleanCut — Product & Technical Spec

> A reseller picks or shoots a product photo. The background is removed on-device,
> the product is placed on a clean studio background with a realistic shadow,
> and the result is exported in marketplace-ready sizes.

## Goals
- **Sellers get a listing-ready photo in under 10 seconds**, with no account and no upload. Everything runs on-device.
- **The result looks professional**: clean edges without halos, a believable shadow, and consistent framing.
- **The UI is clean, professional and intuitive.** The photo is the focus, every change is live and can be undone, and it feels native.

## Non-goals (v1)
OCR fidelity checks, generative backgrounds, manual brush mask editing, accounts/cloud sync, and saving multiple projects (only the last-used style is remembered).

## Features

| Area | Behaviour |
|---|---|
| Import | Photos picker (single & multi), camera (device only), bundled sample photos, drag & drop (iPad/Mac) |
| Segmentation | Vision foreground *instance* mask. Every detected object starts selected; **tap an object to include or exclude it**. A tap on empty background picks the nearest object within a small radius |
| Compositing | Feathered edges, **edge color decontamination (custom Metal CIKernel)**, drop and contact shadows built from the mask. Backgrounds: solid swatches, a custom color, a soft studio-sweep gradient, or transparent |
| Preview | Live `MTKView` preview rendered by a Metal-backed `CIContext` on a proxy image (≤ 1600 px). It always shows the final framed output |
| Framing | Automatic crop and centering around the subject, with a fill ratio set per preset |
| Export | Formats below. Full-quality render only on export. Save to Photos (add-only permission, requested at save time) or Share |
| Batch | Up to 50 photos, the current style applied to all of them, bounded concurrency, a live progress grid, cancel, and per-item retry |
| Benchmark | Vision vs Core ML (U²-Netp, ISNet fp16 / 6-bit palettized) across compute units, run from a macOS CLI |

### Export presets
Defined in one table: [`ExportPreset.swift`](../Kit/CleanCutKit/Recipe/ExportPreset.swift). Marketplaces update their photo guidance, so **check the current rules before relying on these numbers**.

| Preset | Size (px) | Ratio | Fill | Background | File |
|---|---|---|---|---|---|
| Depop | 1280 × 1280 | 1:1 | 80% | any | JPEG |
| Vinted | 1200 × 1500 | 4:5 | 80% | any | JPEG |
| Amazon main | 2000 × 2000 | 1:1 | 85% | forced pure white `#FFFFFF` | JPEG |
| Cutout | 2048 × 2048 | 1:1 | 90% | forced transparent | PNG |

"Fill" is the largest share of the canvas width or height the product may take up.

## UI/UX

**Principles.** The photo is the hero and the chrome stays out of the way. One main action per screen. Presets come first, and fine sliders sit under **Adjust**. Every change is instant and can be undone. Native look and feel: SF Pro, SF Symbols, system materials, haptics.

**Visual language.** A neutral, monochrome UI with **one teal accent** · spacing on an 8-pt scale · corner radii of 12 and 20 pt · Dark Mode, Dynamic Type, VoiceOver and Reduce Motion support · 44-pt minimum tap targets. Tokens live in [`App/DesignSystem`](../App/DesignSystem).

### Screens
1. **Home**: one large "Add product photo" card (Photos / Camera), a quieter "Batch edit" button, and a row of samples to try. One line explains what the app does.
2. **Editor**
   - Top bar: Close · Undo / Redo · **Compare** (press and hold to see the original) · **Export** (the primary action).
   - Canvas: the final framed output in the chosen format's aspect ratio.
   - Format chips above the tools: `1:1 Depop · 4:5 Vinted · Amazon · PNG`.
   - Tool tray with four tabs of at most 3 controls each:
     - **Select**: objects outlined with a soft pulsing glow; tap to toggle (haptic + VoiceOver announcement).
     - **Background**: swatches, studio sweep, transparent, custom color. With the Amazon format the background locks to white, and a note explains why.
     - **Shadow**: `None · Soft · Contact · Natural` plus an intensity slider. Adjust: angle, distance, softness.
     - **Edges**: Clean edges on/off plus strength. Adjust: feather.
   - While Vision runs, a scan shimmer plays over the photo. Then the cutout "lifts" onto the studio background with a spring (skipped when Reduce Motion is on).
   - On iPad and Mac (regular width), the tools move into a right-hand inspector.
3. **Export sheet**: a card per preset with a live thumbnail and the exact pixel size. Pick several, then **Save to Photos** or Share; a checkmark and a success haptic confirm.
4. **Batch**: pick photos, confirm the style and formats, then watch the grid fill in (a progress ring per tile, Cancel, Retry on failed tiles). Finish with "Save all" or Share.
5. **Settings**: segmentation engine (Vision / U²-Net, experimental), a debug HUD (frame time), licenses.

Error messages are written for people, e.g. "No product found — try a photo with a clear subject", never raw error text.

## Technical design
See [ARCHITECTURE.md](ARCHITECTURE.md) for the component view and [DECISIONS.md](DECISIONS.md) for the trade-offs.

- **Pure pipeline:** `Pipeline.makeImage(inputs, recipe, outputSize) -> CIImage`. A `Recipe` is a `Codable`, `Hashable`, `Sendable` value, and all its lengths are relative. The preview and the export call the same function at different output sizes.
- **Swift 6 strict concurrency** with warnings treated as errors. The app target defaults to `MainActor` isolation; the `CleanCutKit` framework is non-isolated and `Sendable`.
- **Targets:** iOS 18+ app; `CleanCutKit` builds for iOS 18 and macOS 15, so tests and benchmarks run natively on a Mac.
