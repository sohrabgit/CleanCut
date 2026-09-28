| Scenario | GPU p50 | GPU p90 | Frame p50 (CPU+GPU) | Frame p90 |
|---|---|---|---|---|
| Redraw, nothing changed | 0.07 ms | 0.11 ms | 0.50 ms | 0.86 ms |
| Drag shadow intensity | 0.38 ms | 0.48 ms | 1.54 ms | 1.77 ms |
| Drag edge-clean strength (re-runs kernel) | 0.20 ms | 0.23 ms | 1.92 ms | 2.15 ms |
| Switch backgrounds | 0.07 ms | 0.08 ms | 0.52 ms | 0.60 ms |
| Drag edge softness (recomputes everything) | 0.93 ms | 1.20 ms | 4.19 ms | 5.11 ms |

120 frames per scenario at 1206×1206 (iPhone 17 Pro width @3×), after 10 warm-up frames. Apple M4 Max, macOS 26.6.2 (Build 25G83).
