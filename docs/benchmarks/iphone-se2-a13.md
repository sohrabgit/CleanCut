# CleanCut benchmarks: iPhone12,8, iOS 26.6.2 (Build 23G90)

2026-09-29. Thermal state nominal at the start, nominal at the end.

## Segmentation

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


## Live preview frame time

| Scenario | GPU p50 | GPU p90 | Frame p50 (CPU+GPU) | Frame p90 |
|---|---|---|---|---|
| Redraw, nothing changed | 0.83 ms | 0.85 ms | 2.58 ms | 3.09 ms |
| Drag shadow intensity | 3.02 ms | 3.05 ms | 8.40 ms | 8.61 ms |
| Drag edge-clean strength (re-runs kernel) | 1.75 ms | 1.77 ms | 4.46 ms | 4.66 ms |
| Switch backgrounds | 0.86 ms | 1.14 ms | 2.87 ms | 3.41 ms |
| Drag edge softness (recomputes everything) | 6.16 ms | 6.94 ms | 14.49 ms | 15.63 ms |

5 scenarios at 750×750 (this screen's width in pixels). iPhone12,8, iOS 26.6.2 (Build 23G90).


## Guided capture analysis

| Step | p50 | p90 |
|---|---|---|
| Frame statistics (two kernels + GPU reduction) | 12.7 ms | 14.6 ms |
| Subject mask (U²-Netp `liveMask`, 1 frame in 3) | 29.6 ms | 31.6 ms |
| **Per frame, as scheduled** (mean 22.5 ms) | **13.0 ms** | **44.9 ms** |

Replay frames at 1080×1440 in camera-like pixel buffers. Budget at 15 fps: 66.7 ms. iPhone12,8, iOS 26.6.2 (Build 23G90).
