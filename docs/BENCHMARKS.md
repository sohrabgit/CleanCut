# Benchmarks

All numbers were measured on an **Apple M4 Max, macOS 26.6** with the `cleancut-bench` CLI. It uses the same `CleanCutKit` code the iOS app ships. iPhone numbers aren't included yet. The harness (`SegmentationBenchmark`) lives in the framework, so an on-device "Lab" screen is a small follow-up.

Reproduce:

```sh
make -C Tools/ModelConversion          # converts U²-Netp + ISNet into Models/
make bench                             # builds the CLI
B=.build/dd/Build/Products/Release/cleancut-bench
$B segment <photo-folder> --count 12 --runs 30 --report docs/benchmarks/segmentation-m4max.md
$B batch   <photo-folder> --concurrency 1,2,4 --report docs/benchmarks/batch-memory.md
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

## 2. Batch mode: bounded memory

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

## 3. Pipeline correctness

The pipeline test suite checks these invariants on every run (see `Tests/CleanCutKitTests`):
- the Amazon preset's background is exactly `(255, 255, 255)` even under a natural shadow;
- the subject is centered and fills exactly the preset's fill ratio;
- **preview/export parity**: a 320 px preview matches a 1280 px export downscaled, with PSNR > 32 dB;
- the edge-decontamination kernel cuts the edge color error by at least 60% on a synthetic green-screen fringe and leaves the interior bit-identical;
- rendering is deterministic.
