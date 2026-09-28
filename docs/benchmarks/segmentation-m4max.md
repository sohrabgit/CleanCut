| Engine | Compute units | Size | Load | Reload | First run | Inference p50 | p90 | End-to-end p50 | IoU vs Vision | Peak mem |
|---|---|---|---|---|---|---|---|---|---|---|
| Vision | Auto | system | lazy | lazy | 15.2 ms | **15.0 ms** | 15.5 ms | 15.0 ms | ref. | 13 MB |
| Vision | ANE | system | lazy | lazy | 15.0 ms | **15.0 ms** | 15.4 ms | 15.0 ms | 1.000 | 14 MB |
| Vision | GPU | system | lazy | lazy | 107 ms | **16.5 ms** | 16.9 ms | 16.5 ms | 1.000 | 159 MB |
| Vision | CPU | – | – | – | – | unsupported | – | – | – | – |
| U2Netp | CPU | 2.4 MB | 21.0 ms | 19.4 ms | 26.7 ms | **16.9 ms** | 17.1 ms | 21.6 ms | 0.958 | 76 MB |
| U2Netp | CPU+GPU | 2.4 MB | 23.6 ms | 21.8 ms | 34.5 ms | **5.2 ms** | 5.7 ms | 8.0 ms | 0.958 | 88 MB |
| U2Netp | CPU+ANE | 2.4 MB | 24.7 ms | 22.9 ms | 9.3 ms | **4.6 ms** | 4.8 ms | 7.9 ms | 0.958 | 25 MB |
| U2Netp | All | 2.4 MB | 27.7 ms | 25.8 ms | 21.5 ms | **7.5 ms** | 7.8 ms | 10.6 ms | 0.958 | 68 MB |
| ISNet-6bit | CPU | 31.8 MB | 23.0 ms | 21.9 ms | 126 ms | **103 ms** | 105 ms | 107 ms | 0.955 | 189 MB |
| ISNet-6bit | CPU+GPU | 31.8 MB | 27.5 ms | 26.3 ms | 287 ms | **26.5 ms** | 26.5 ms | 29.4 ms | 0.955 | 624 MB |
| ISNet-6bit | CPU+ANE | 31.8 MB | 50.4 ms | 28.6 ms | 31.1 ms | **24.2 ms** | 24.3 ms | 28.6 ms | 0.955 | 91 MB |
| ISNet-6bit | All | 31.8 MB | 33.3 ms | 30.3 ms | 55.6 ms | **37.5 ms** | 38.3 ms | 42.1 ms | 0.955 | 221 MB |
| ISNet | CPU | 84.2 MB | 19.4 ms | 18.6 ms | 125 ms | **103 ms** | 104 ms | 107 ms | 0.956 | 240 MB |
| ISNet | CPU+GPU | 84.2 MB | 28.8 ms | 26.6 ms | 57.8 ms | **26.5 ms** | 26.5 ms | 29.4 ms | 0.956 | 246 MB |
| ISNet | CPU+ANE | 84.2 MB | 49.1 ms | 27.5 ms | 33.1 ms | **25.1 ms** | 25.3 ms | 29.6 ms | 0.956 | 87 MB |
| ISNet | All | 84.2 MB | 32.3 ms | 29.7 ms | 57.5 ms | **38.7 ms** | 39.2 ms | 43.2 ms | 0.956 | 223 MB |

12 photos (≤ 2048 px), 5 warm-up + 30 measured runs per row. Apple M4 Max, macOS 26.6.2 (Build 25G83).
