
<!-- README.md is generated from README.Rmd. Please edit that file -->

# pie

<!-- badges: start -->

<!-- (Optional) Add your badges once you set up CI -->

<!-- [![R-CMD-check](https://github.com/alazarovski/pie/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/alazarovski/pie/actions/workflows/R-CMD-check.yaml) -->

<!-- badges: end -->

**pie** provides tools to compute and visualize the **PIE
(Path/Procedure Inefficiency)** indicator for aviation sustainability
and flight efficiency.  
It focuses on: - Turning flight trajectories and airport metadata into
**segment-level** and **flight-level** PIE metrics. - Handling **TMA
radius** logic, **entry/exit detection**, and **great-circle
baselines**. - Producing quick plots/tables for validation and
reporting.

> ⚠️ This is a work-in-progress. APIs may change. Feel free to open
> issues/PRs.

## Installation

Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("alazarovski/pie")
```

## Quick start

Below is a *template* workflow you can adapt. Chunks use `eval = FALSE`
so the README knits before you’ve implemented everything.

``` r
library(pie)
library(data.table)
library(sf)
```

### 1) Input data (example schema)

``` r
# Minimal columns expected (customize to your real schema)
flights <- data.table::data.table(
  FLT_ID = c("AZ123", "LH456"),
  ADEP = c("LIRF", "EDDF"),
  ADES = c("EBBR", "LFPG")
)

# Trajectory points (WGS84) with ordering & timestamps
traj <- data.table::data.table(
  FLT_ID = c("AZ123","AZ123","AZ123","LH456","LH456"),
  SEQ_ID = c(1L,2L,3L,1L,2L),
  LON = c(12.24, 6.95, 4.48, 8.56, 6.11),
  LAT = c(41.80, 50.03, 50.90, 50.04, 49.00),
  TIME_OVER = as.POSIXct(c(
    "2025-01-01 10:00:00","2025-01-01 10:50:00","2025-01-01 11:05:00",
    "2025-01-01 09:35:00","2025-01-01 09:58:00"
  ), tz = "UTC")
)
```

### 2) Build segments & baseline

``` r
# Segments from ordered points
seg <- pie::segments_from_points(traj,
  id_cols = c("FLT_ID"),
  lon = "LON", lat = "LAT",
  seq_col = "SEQ_ID"
)

# Great-circle baseline distance (ADEP→ADES)
flights <- pie::add_gc_baseline(flights)
```

### 3) Compute PIE

``` r
# Example: within a given TMA radius (nm) around ADES, or en-route only
pie_result <- pie::compute_pie(
  segments = seg,
  flights  = flights,
  mode = c("tma","enroute","full"), # choose what you implement
  tma_radius_nm = 40
)

# Summaries per flight
pie_flt <- pie::summarize_pie(pie_result, by = "FLT_ID")
```

### 4) Plot & inspect

``` r
pie::plot_pie_distribution(pie_flt)

# Map check (if you implement sf/leaflet plotting helpers)
pie::plot_trajectory_map(seg[FLT_ID == "AZ123"])
```

## What is PIE?

**PIE** ≈ *observed path vs. ideal baseline* inefficiency metric (you
decide the exact formula).  
Common approaches: - Baseline: **great-circle** distance or a reference
**procedural path**. - Observed: polyline length of the flown trajectory
or segment subset (e.g., inside TMA). - Output: absolute extra
distance/time/fuel or **% inefficiency**.

This package aims to keep that logic **transparent** and
**configurable**.

## Minimal API (to implement)

> Stub signatures you can copy into `R/` files and fill in.

``` r
#' Build segments from ordered points
#' @param dt data.table with point rows
#' @param id_cols character vector of ID columns (e.g., c("FLT_ID"))
#' @param lon,lat names of lon/lat columns
#' @param seq_col ordering column within each id
#' @return data.table of segments (LINESTRING or start/end pairs)
segments_from_points <- function(dt, id_cols, lon, lat, seq_col) {
  stop("Not implemented yet.")
}

#' Add great-circle baseline distance between ADEP and ADES
#' @param flights data.table with ADEP/ADES
#' @return flights with gc_baseline_nm
add_gc_baseline <- function(flights) {
  stop("Not implemented yet.")
}

#' Compute PIE metric
#' @param segments segment table (possibly with sf geometry)
#' @param flights flight table with baseline metric
#' @param mode "tma", "enroute", or "full"
#' @param tma_radius_nm numeric radius for TMA computations
#' @return data.table with per-segment and/or per-flight PIE components
compute_pie <- function(segments, flights, mode = "full", tma_radius_nm = 40) {
  stop("Not implemented yet.")
}

#' Summarize PIE by grouping key(s)
summarize_pie <- function(pie_dt, by = "FLT_ID") {
  stop("Not implemented yet.")
}
```

## Reproducible chunks in README

You can run normal R code here as well:

``` r
summary(cars)
#>      speed           dist       
#>  Min.   : 4.0   Min.   :  2.00  
#>  1st Qu.:12.0   1st Qu.: 26.00  
#>  Median :15.0   Median : 36.00  
#>  Mean   :15.4   Mean   : 42.98  
#>  3rd Qu.:19.0   3rd Qu.: 56.00  
#>  Max.   :25.0   Max.   :120.00
```

You can also embed plots:

<img src="man/figures/README-pressure-1.png" width="100%" />

Remember to re-knit when code or figures change:

``` r
devtools::build_readme()  # keeps README.md in sync
```

## Contributing

PRs welcome. Please open an issue to discuss substantial changes.

## License

MIT © Antonio Lazarovski
