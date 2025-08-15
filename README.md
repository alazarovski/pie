
# pie

<!-- badges: start -->

<!-- (Optional) Add your badges once you set up CI) -->

<!-- [![R-CMD-check](https://github.com/alazarovski/pie/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/alazarovski/pie/actions/workflows/R-CMD-check.yaml) -->

<!-- badges: end -->

Tools to compute and explore the **PIE (Path InEfficiency)** indicator
for aviation sustainability and flight efficiency, built around
**trajectory points → segments → metrics**. This README uses only the
three exported functions you’ve implemented:

- `compute_pie_metrics()` — end‑to‑end helper that segments
  trajectories, joins airport coordinates, computes along‑track /
  cross‑track / segment distances, and returns a `pie` (%).
- `pt_to_seg_trj()` — converts ordered points per flight into
  **segments** (entry→exit).
- `read_openflights_airports()` — reads + normalizes OpenFlights’
  `airports.dat` (readr backend).

> If your project was created with `usethis::use_readme_rmd()`, you may
> also have a `README.Rmd` and a Git hook that requires knitting. This
> file is plain Markdown; if that hook is enabled you’ll need to **knit
> your README.Rmd** or remove the hook before committing this file.

------------------------------------------------------------------------

## What is PIE?

**(PIE)** measures deviation from an ideal, *direct‑to‑destination path
(DDP)* over short segments. For each segment:

- **Along‑track distance** $x$: distance progressed toward destination
  along the great circle from segment start.
- **Cross‑track distance** $y$: perpendicular offset from that
  great‑circle path.
- **PIE** is defined here as an integer percent:

$$
\mathrm{PIE} = \mathrm{round}\left( 100 \times \frac{y}{x} \right)
$$

Both $x$ and $y$ are computed as great‑circle distances (meters).
Segment length is reported via the Haversine distance.

### Extra Distance (ED) transfer (concept)

When attribution matters (e.g., between airspaces), you can attribute
“downstream” extra distance using:

$$
ED_C = S_C \times PIE_B
$$

where $S_C$ is the path length flown in Airspace C, and $PIE_B$ is the
inefficiency observed earlier in B. This package exposes the
**per‑segment PIE** you can aggregate to such constructs.

------------------------------------------------------------------------

## Installation

``` r
# install.packages("pak")
pak::pak("alazarovski/pie")
```

------------------------------------------------------------------------

## Functions at a glance

### `compute_pie_metrics(trj_pt, airports = NULL, cols = list(...), order_by = c("flid","time_over"), quiet = TRUE)`

- **Input**: point‑wise trajectories (`data.table`/`data.frame`).
  - Required columns via `cols` mapping: `fl_id`, `lon`, `lat`,
    `time_over` (POSIXct), and typically `adep`, `ades`. `seq_id` is
    optional.
- **What it does**:
  1.  Calls `pt_to_seg_trj()` to build **segments**.
  2.  Loads airports via `read_openflights_airports()` (or use your own
      with `airports=`).
  3.  Computes:
      - `gc_along_track_dist` (meters),
      - `gc_cross_track_dist` (meters, absolute value used in PIE),
      - `seg_distance` (Haversine meters).
  4.  Adds integer `pie` (%).
- **Output**: a `data.table` of segments with coordinates, optional
  times/altitudes, distances, and `pie`.

### `pt_to_seg_trj(trj_data, cols, order_by = c("seq_id","time_over","none"), ...)`

- Builds **one row per adjacent point pair** per flight.
- Requires `fl_id`, `lon`, `lat`, `time_over`; `adep` and `ades` are
  strongly recommended.
- Can compute `dist_m`, `dist_nm`, `dur_s`, and creates a stable
  `seg_id`.

### `read_openflights_airports(path, check = TRUE, keep = NULL)`

- Reads OpenFlights’ `airports.dat` with `readr`, normalizes codes to
  uppercase, validates ranges, and optionally **keeps a subset** of
  columns (e.g., `keep = c("icao_code","longitude","latitude")`).

> **Units**: distances are **meters** (from `geosphere`), nautical miles
> are provided by `pt_to_seg_trj()` if `compute_distance = TRUE` (via
> `dist_nm`). The `pie` column is an **integer percent**.

------------------------------------------------------------------------

## Quick start

``` r
library(pie)
library(data.table)

# Example trajectory points with altitude and timestamps
trj_pts <- data.table::data.table(
  fl_id     = c(1, 1, 1,  2, 2),
  seq_id    = c(1, 2, 3,  1, 2),
  lon       = c(4.484, 4.500, 4.520,  6.10, 6.30),
  lat       = c(50.900, 51.000, 51.100, 49.90, 50.05),
  altitude  = c(0, 1500, 3000,  0, 1200),   # feet (optional)
  time_over = as.POSIXct(c(
                 "2025-08-14 12:00:00",
                 "2025-08-14 12:02:00",
                 "2025-08-14 12:04:00",
                 "2025-08-14 12:10:00",
                 "2025-08-14 12:12:00"
               ), tz = "UTC"),
  adep      = c("EBBR","EBBR","EBBR",  "EDDF","EDDF"),
  ades      = c("LFPG","LFPG","LFPG",  "EBBR","EBBR")
)

# End-to-end PIE computation (uses online OpenFlights by default)
seg_pie <- compute_pie_metrics(
  trj_pts,
  cols = list(
    fl_id     = "fl_id",
    seq_id    = "seq_id",     # optional; if omitted, order_by="time_over" will generate it
    lon       = "lon",
    lat       = "lat",
    altitude  = "altitude",   # optional
    time_over = "time_over",
    adep      = "adep",
    ades      = "ades"
  ),
  order_by = "time_over",     # or "seq_id" if a clean sequence is present
  quiet = TRUE
)

# Inspect
data.table::setDT(seg_pie)[]
```

### Summaries

``` r
# simple unweighted average PIE per flight
seg_pie[ , .(pie_avg = mean(pie, na.rm = TRUE)), by = fl_id][order(fl_id)]
```

``` r
# if seg_distance is present (meters), use it as weight
seg_pie[ , .(
  pie_wavg = round(weighted.mean(pie, w = seg_distance, na.rm = TRUE), 1)
), by = fl_id][order(fl_id)]
```

### Offline / deterministic airports

``` r
airports <- read_openflights_airports(
  keep = c("icao_code","longitude","latitude")
)

seg_pie <- compute_pie_metrics(
  trj_pts,
  cols = list(
    fl_id     = "fl_id",
    seq_id    = "seq_id",
    lon       = "lon",
    lat       = "lat",
    altitude  = "altitude",
    time_over = "time_over",
    adep      = "adep",
    ades      = "ades"
  ),
  order_by = "time_over",
  airports = airports,  # use local copy
  quiet = TRUE
)
```

### Using the lower‑level segmenter directly

``` r
# Build segments only; you control what happens next
seg_only <- pt_to_seg_trj(
  trj_pts,
  cols = list(
    fl_id     = "fl_id",
    seq_id    = "seq_id",
    lon       = "lon",
    lat       = "lat",
    time_over = "time_over",
    adep      = "adep",
    ades      = "ades"
  ),
  order_by = "time_over",
  compute_distance = TRUE,
  compute_duration = TRUE
)

seg_only[]
```

------------------------------------------------------------------------

## Column contracts & tips

- **Required for segmentation**: `fl_id`, `lon`, `lat`, `time_over`
  (POSIXct). `adep`/`ades` are used by `compute_pie_metrics()` to anchor
  the great‑circle to the **destination**.
- **Ordering**: If you do **not** provide `seq_id`, use
  `order_by = "time_over"` so `pt_to_seg_trj()` creates a consistent
  sequence within each flight.
- **PIE denominator**: Segments with **non‑positive** or **undefined**
  along‑track distance are left as `pie = NA`. Filter or impute as
  appropriate.
- **Units**: outputs from `geosphere` are **meters**. `pt_to_seg_trj()`
  also provides `dist_nm` when `compute_distance=TRUE`.
- **Performance**: both helpers are vectorized and operate on
  `data.table`s; set keys/indexes downstream as needed.

------------------------------------------------------------------------

## Troubleshooting

- **“airports.dat cannot be read”** — some environments block remote
  reads. Use `read_openflights_airports(keep=...)` once and pass the
  resulting table via `airports=` to `compute_pie_metrics()`.
- **“time_over must be POSIXt”** — ensure your timestamp column is
  `POSIXct`. Convert with `as.POSIXct(..., tz = "UTC")`.
- **Git hook complains “README.md is out of date”** — if you have
  `README.Rmd`, knit it (`devtools::build_readme()`), or remove/adjust
  the hook if you prefer a plain Markdown README.

------------------------------------------------------------------------

## Contributing

Issues and PRs are welcome. Please open an issue first for substantial
changes or API proposals.

## License

MIT © Antonio Lazarovski
