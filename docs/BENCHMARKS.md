# Benchmarks

Two machines: an **iPhone SE (2nd generation, A13 Bionic), iOS 26.6.2**, measured by the app's Settings › Benchmarks screen, and an **Apple M4 Max, macOS 26.6**, measured by the `cleancut-bench` CLI. Both run the same harnesses from `CleanCutKit/Bench` (`SegmentationBenchmark`, `PreviewBenchmark`, `CaptureBenchmark`) on the code the app ships, in Release builds. The iPhone SE is a deliberately low bar: a 2020 phone with the oldest chip that runs iOS 26.

Reproduce:

```sh
make -C Tools/ModelConversion          # converts U²-Netp + ISNet into Models/
make bench                             # builds the CLI
B=.build/dd/Build/Products/Release/cleancut-bench
$B segment <photo-folder> --count 12 --runs 30 --report docs/benchmarks/segmentation-m4max.md
$B batch   <photo-folder> --concurrency 1,2,4 --report docs/benchmarks/batch-memory.md
$B preview <photo> --report docs/benchmarks/preview-m4max.md
```

## iPhone SE (2nd generation, A13 Bionic)

Settings › Benchmarks, one run, thermal state nominal from start to end. Report: [`iphone-se2-a13.md`](benchmarks/iphone-se2-a13.md), raw data: [`iphone-se2-a13.csv`](benchmarks/iphone-se2-a13.csv).

**Segmentation**

| Engine | Compute units | Size | Load | Reload | First run | Inference p50 | p90 | End-to-end p50 | IoU vs Vision | Peak mem |
|---|---|---|---|---|---|---|---|---|---|---|
| Vision | Auto | system | lazy | lazy | 64.4 ms | **53.6 ms** | 54.6 ms | 53.6 ms | ref. | 4 MB |
| Vision | ANE | system | lazy | lazy | 53.3 ms | **53.7 ms** | 54.4 ms | 53.7 ms | 1.000 | 3 MB |
| Vision | GPU | system | lazy | lazy | 488 ms | **137 ms** | 140 ms | 137 ms | 1.000 | 112 MB |
| Vision | CPU | – | – | – | – | unsupported | – | – | – | – |
| U²-Netp | CPU | 2.4 MB | 77.7 ms | 49.0 ms | 115 ms | **67.2 ms** | 67.5 ms | 76.2 ms | 0.997 | 66 MB |
| U²-Netp | CPU+GPU | 2.4 MB | 165 ms | 130 ms | 197 ms | **95.5 ms** | 97.6 ms | 128 ms | 0.997 | 67 MB |
| U²-Netp | CPU+ANE | 2.4 MB | 254 ms | 151 ms | 42.0 ms | **22.1 ms** | 24.2 ms | 31.7 ms | 0.997 | 21 MB |
| U²-Netp | All | 2.4 MB | 189 ms | 167 ms | 49.7 ms | **35.8 ms** | 36.7 ms | 52.1 ms | 0.997 | 29 MB |

3 photos (≤ 2048 px), 5 warm-up + 30 measured runs per row. iPhone12,8, iOS 26.6.2 (Build 23G90).

**Live preview** (the SE's screen is 60 Hz, so the budget is 16.7 ms)

| Scenario | GPU p50 | GPU p90 | Frame p50 (CPU+GPU) | Frame p90 |
|---|---|---|---|---|
| Redraw, nothing changed | 0.83 ms | 0.85 ms | 2.58 ms | 3.09 ms |
| Drag shadow intensity | 3.02 ms | 3.05 ms | 8.40 ms | 8.61 ms |
| Drag edge-clean strength (re-runs kernel) | 1.75 ms | 1.77 ms | 4.46 ms | 4.66 ms |
| Switch backgrounds | 0.86 ms | 1.14 ms | 2.87 ms | 3.41 ms |
| Drag edge softness (recomputes everything) | 6.16 ms | 6.94 ms | 14.49 ms | 15.63 ms |

5 scenarios at 750×750 (this screen's width in pixels). iPhone12,8, iOS 26.6.2 (Build 23G90).

**Guided capture analysis**

| Step | p50 | p90 |
|---|---|---|
| Frame statistics (two kernels + GPU reduction) | 12.7 ms | 14.6 ms |
| Subject mask (U²-Netp `liveMask`, 1 frame in 3) | 29.6 ms | 31.6 ms |
| **Per frame, as scheduled** (mean 22.5 ms) | **13.0 ms** | **44.9 ms** |

Replay frames at 1080×1440 in camera-like pixel buffers. Budget at 15 fps: 66.7 ms. iPhone12,8, iOS 26.6.2 (Build 23G90).

**What I take from it**
1. **Pinning compute units holds on the A13.** U²-Netp takes 22.1 ms on CPU+ANE and 35.8 ms with `.all`, the same ordering as on the M4 Max (ADR 008). On this chip the GPU is *slower than the CPU* for U²-Netp (95.5 vs 67.2 ms), so on older phones the Neural Engine is the only fast path.
2. **Segmentation is 3.6–4.8× slower than on the M4 Max** (Vision 53.6 vs 15.0 ms, U²-Netp 22.1 vs 4.6 ms), which still fits "open a photo, see the cutout" comfortably. Vision pinned to the GPU costs 137 ms and a 488 ms first run: another reason to leave placement to Vision.
3. **The preview fits a 60 Hz frame, with little margin in the worst case.** Ordinary edits take 3.1–8.6 ms per frame (p90). The worst case, where every frame gets a new matte and everything downstream recomputes, is 15.6 ms at p90 against a 16.7 ms budget. That's the first place to optimize for older phones (for example, a lower-resolution matte while a slider is being dragged).
4. **Guided capture has about 3× headroom at 15 fps.** A frame costs 22.5 ms on average against a 66.7 ms budget. Frames that also refresh the subject mask take 45 ms (p90). A mask on every frame (about 42 ms) would still fit, but with little room left for the camera, the preview and the phone's temperature. Refreshing it on one frame in three keeps the average low.

**Caveats.** Three photos (the bundled development samples), so the IoU column says little beyond "the engines agree on simple product shots". The timings don't depend on content. The capture numbers use replay frames in camera-like pixel buffers, not the live camera; the frame-timing HUD shows the live number on the capture screen. The first Neural Engine load (254 ms here) may include the one-time on-device compile; I didn't separate the two on the phone.

Reproduce: open Settings › Benchmarks and tap Run Benchmarks, then Share Report. Or run it from a Mac without touching the phone:

```sh
xcrun devicectl device process launch --device <udid> --terminate-existing dev.sohrab.cleancut -runLab
xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
  --domain-identifier dev.sohrab.cleancut --source Documents/Benchmarks --destination .bench/device
```

## 1. Segmentation: Vision vs Core ML across compute units

| Engine | Compute units | Size | Load | Reload | First run | Inference p50 | p90 | End-to-end p50 | IoU vs Vision | Peak mem |
|---|---|---|---|---|---|---|---|---|---|---|
| Vision | Auto | system | lazy | lazy | 15.2 ms | **15.0 ms** | 15.5 ms | 15.0 ms | ref. | 13 MB |
| Vision | ANE | system | lazy | lazy | 15.0 ms | **15.0 ms** | 15.4 ms | 15.0 ms | 1.000 | 12 MB |
| Vision | GPU | system | lazy | lazy | 107 ms | **16.5 ms** | 16.9 ms | 16.5 ms | 1.000 | 158 MB |
| Vision | CPU | – | – | – | – | unsupported | – | – | – | – |
| U²-Netp | CPU | 2.4 MB | 21.0 ms | 19.4 ms | 26.7 ms | **16.9 ms** | 17.1 ms | 21.6 ms | 0.958 | 75 MB |
| U²-Netp | CPU+GPU | 2.4 MB | 23.6 ms | 21.8 ms | 34.5 ms | **5.2 ms** | 5.7 ms | 7.8 ms | 0.958 | 86 MB |
| U²-Netp | CPU+ANE | 2.4 MB | 24.7 ms | 22.9 ms | 9.3 ms | **4.6 ms** | 4.8 ms | 7.8 ms | 0.958 | 25 MB |
| U²-Netp | All | 2.4 MB | 27.7 ms | 25.8 ms | 21.5 ms | **7.5 ms** | 7.8 ms | 10.2 ms | 0.958 | 13 MB |
| ISNet 6-bit | CPU | 31.8 MB | 23.0 ms | 21.9 ms | 126 ms | **103 ms** | 105 ms | 107 ms | 0.955 | 216 MB |
| ISNet 6-bit | CPU+GPU | 31.8 MB | 27.5 ms | 26.3 ms | 287 ms | **26.5 ms** | 26.5 ms | 29.1 ms | 0.955 | 625 MB |
| ISNet 6-bit | CPU+ANE | 31.8 MB | 50.4 ms | 28.6 ms | 31.1 ms | **24.2 ms** | 24.3 ms | 28.7 ms | 0.955 | 0 MB |
| ISNet 6-bit | All | 31.8 MB | 33.3 ms | 30.3 ms | 55.6 ms | **37.5 ms** | 38.3 ms | 42.3 ms | 0.955 | 139 MB |
| ISNet fp16 | CPU | 84.2 MB | 19.4 ms | 18.6 ms | 125 ms | **103 ms** | 104 ms | 107 ms | 0.956 | 240 MB |
| ISNet fp16 | CPU+GPU | 84.2 MB | 28.8 ms | 26.6 ms | 57.8 ms | **26.5 ms** | 26.5 ms | 29.5 ms | 0.956 | 284 MB |
| ISNet fp16 | CPU+ANE | 84.2 MB | 49.1 ms | 27.5 ms | 33.1 ms | **25.1 ms** | 25.3 ms | 29.8 ms | 0.956 | 0 MB |
| ISNet fp16 | All | 84.2 MB | 32.3 ms | 29.7 ms | 57.5 ms | **38.7 ms** | 39.2 ms | 42.4 ms | 0.956 | 252 MB |

The input was 12 photos at ≤ 2048 px, with 5 warm-up and 30 measured runs per row. Raw data: [`segmentation-m4max.csv`](benchmarks/segmentation-m4max.csv).

**How to read it**
- **Load** is a fresh process loading a compiled `.mlmodelc` from a stable path. **Reload** loads it again in the same process. Vision loads its model lazily inside the first request.
- **The first load on the Neural Engine is much slower.** The very first time a model is loaded on the Neural Engine, macOS compiles it for that hardware: **0.67 s for U²-Netp and 8.4–9.0 s for ISNet** on this Mac. After that, the OS caches the result keyed by model location, and later process launches load in about 25–50 ms (the "Load" column). A model compiled to a new temporary path misses the cache every time.
- **Inference** is the model call alone. **End-to-end** also covers preprocessing (Core ML's own resize into the input buffer) and post-processing (upsampling the mask to the photo and building the label map). Vision is a black box, so its two columns are the same.
- **IoU vs Vision** measures how much each mask *agrees* with Vision's (1 = identical). It is not accuracy against ground truth: on these simple, studio-like photos every engine finds the product. Content changes this number; the timings are independent of content.
- **Peak mem** is the rise in the process footprint during the row. It's noisy because the OS shares model memory between rows. "0 MB" means it was absorbed by memory already mapped.

**What I take from it**
1. **Pin the compute units; `.all` isn't the fastest.** Every model got *slower* with `.all` than with CPU+GPU or CPU+ANE alone. ISNet went from 24 ms to 38 ms, probably from graph partitioning and handoffs between devices. The app runs U²-Netp on `.cpuAndNeuralEngine`.
2. **The Neural Engine wins on steady-state latency, and costs a one-time compile.** For a feature on the critical path (open photo → cutout), prewarm the model in the background on first launch. Otherwise the first user pays up to 9 s.
3. **6-bit palettization is nearly free here.** ISNet shrinks from 84 MB to 32 MB (2.6× smaller) with the same latency on the GPU and Neural Engine, and its agreement with Vision drops from 0.956 to 0.955. For an app download size, that's an easy trade.
4. **Vision is the practical default.** At about 15 ms on the Neural Engine it gives separate instances (tap-to-select), a mask guided to full resolution, and no bundled weights. U²-Netp is the fallback: 3× faster, 2.4 MB, and it runs in the Simulator, where Vision's instance mask can't.

## 2. Live preview frame time

`cleancut-bench preview <photo>` renders frames exactly like the editor does: the proxy inputs and the shared GPU context drawing into a Metal texture the size of a drawable. Each scenario changes one parameter per frame, as a slider drag would.

| Scenario | GPU p50 | GPU p90 | Frame p50 (CPU+GPU) | Frame p90 |
|---|---|---|---|---|
| Redraw, nothing changed | 0.07 ms | 0.11 ms | 0.50 ms | 0.86 ms |
| Drag shadow intensity | 0.38 ms | 0.48 ms | 1.54 ms | 1.77 ms |
| Drag edge-clean strength (re-runs kernel) | 0.20 ms | 0.23 ms | 1.92 ms | 2.15 ms |
| Switch backgrounds | 0.07 ms | 0.08 ms | 0.52 ms | 0.60 ms |
| Drag edge softness (recomputes everything) | 0.93 ms | 1.20 ms | 4.19 ms | 5.11 ms |

120 frames per scenario at 1206×1206 (iPhone 17 Pro width @3×), after 10 warm-up frames. Apple M4 Max, macOS 26.6.2 (Build 25G83).

- **Budget:** 16.7 ms per frame at 60 Hz and 8.3 ms at 120 Hz. Even the worst case, where every frame gets a new matte and so the kernel, cutout and shadows all recompute, leaves about 3× headroom on this Mac. On the iPhone SE the same case takes 15.6 ms at p90 ([above](#iphone-se-2nd-generation-a13-bionic)). The HUD in Settings shows frame times live.
- Cheap edits stay cheap because Core Image reuses unchanged subgraphs: the cutout is an explicit cached intermediate. Changing the backdrop costs as much as a redraw.

## 3. Batch mode: bounded memory

| Concurrency | Photos | Wall time | Per photo | Peak footprint | Above baseline |
|---|---|---|---|---|---|
| 1 | 45 | 6.3 s | 0.14 s | 872 MB | 868 MB |
| 2 | 45 | 3.1 s | 0.07 s | 996 MB | 675 MB |
| 4 | 45 | 1.8 s | 0.04 s | 1399 MB | 1028 MB |

The input was 50 photos at 4032×3024, decoded to ≤ 3072 px, and exported as Depop + Amazon. Five photos had no detectable product and failed on purpose. The footprint *between* photos stays flat at 400–600 MB for the whole batch; the peaks come from rendering in progress.

**The finding behind these numbers** ([DECISIONS 006](DECISIONS.md#006--a-short-lived-cicontext-per-photo-not-one-for-the-whole-app)). The first version reused one `CIContext` for the whole batch and peaked at **2.9 GB with a single worker**. `cleancut-bench memprobe` showed where the memory went:

| Stage (12 photos, one shared context) | Footprint after photo 1 → 12 |
|---|---|
| decode only | 7 → 9 MB |
| + Vision | 211 → 215 MB (model loaded once) |
| + full-res mask | 260 → 265 MB |
| + export render | 500 → **1,687 MB** |
| + export render, fresh context per photo | 493 → **~595 MB (flat)** |

`clearCaches()`, `cacheIntermediates: false` and `.memoryTarget` did not release the growth. Only dropping the context did.

## 4. Pipeline correctness

The pipeline test suite checks these invariants on every run (see `Tests/CleanCutKitTests`):
- the Amazon preset's background is exactly `(255, 255, 255)` even under a natural shadow;
- the subject is centered and fills exactly the preset's fill ratio;
- **preview/export parity**: a 320 px preview matches a 1280 px export downscaled, with PSNR > 32 dB;
- the edge-decontamination kernel cuts the edge color error by at least 60% on a synthetic green-screen fringe and leaves the interior bit-identical;
- rendering is deterministic.
