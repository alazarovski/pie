#' Build segment trajectories from point trajectories
#'
#' @description
#' Converts a point-wise trajectory table (one row per point) into a segment-wise
#' table (one row per adjacent point pair) per flight. Columns may have arbitrary
#' names in the input; map them via `cols`.
#'
#' @param trj_data A `data.frame` or `data.table` with point trajectories.
#' @param cols Named list mapping **canonical** names used internally to the
#'   column names present in `trj_data`. Minimum required keys:
#'   `fl_id`, `seq_id`, `lon`, `lat`. Optional: `altitude`, `time_over`, `adep`, `ades`.
#'   Example:
#'   `list(fl_id="flight_id", seq_id="seq", lon="longitude", lat="latitude",
#'   altitude="fl", time_over="ts", adep="dep", ades="arr")`.
#' @param order_by One of `c("seq_id","time_over","none")`. How to order points within each flight
#'   before segmenting. Default `"seq_id"`.
#' @param keep_cols Character vector of **additional** columns in `trj_data` to carry
#'   through (from the entry point row). Use when you want to preserve extra attributes.
#' @param drop_incomplete Logical, default `TRUE`. If `TRUE`, drops the last point
#'   of each flight that lacks an exit (lead) point, i.e., segments with `NA` exit.
#' @param compute_distance Logical, default `FALSE`. If `TRUE`, computes 2D great-circle
#'   distance per segment (meters and nautical miles) using `geosphere::distHaversine()`.
#' @param compute_duration Logical, default `FALSE`. If `TRUE` and `time_over` is present,
#'   computes segment duration in seconds.
#' @param make_segment_id Logical, default `TRUE`. If `TRUE`, creates a `seg_id`
#'   of the form `"<fl_id>:<e_seq_id>><x_seq_id>"`.
#'
#' @returns A `data.table` with one row per segment containing:
#' - `fl_id`, `e_seq_id`, `x_seq_id`
#' - entry/exit coordinates: `e_lon`, `e_lat`, `x_lon`, `x_lat`
#' - optionally `e_alt`, `x_alt`, `e_time`, `x_time`, `adep`, `ades`
#' - optional computed metrics (`dist_m`, `dist_nm`, `dur_s`)
#' - optional `seg_id`
#' - any `keep_cols` copied from the entry row
#'
#' @section Column mapping:
#' Canonical names used internally: `fl_id`, `seq_id`, `lon`, `lat`,
#' optional `altitude`, `time_over`, `adep`, `ades`. Map them from your input
#' once via `cols`; the function renames on a **copy** and never mutates `trj_data`.
#'
#' @examples
#' \dontrun{
#' library(data.table)
#' pts <- data.table(
#'   flight = c(1,1,1, 2,2),
#'   seq    = c(1,2,3, 1,2),
#'   lon    = c(0, 0.5, 1.0, 0,  1),
#'   lat    = c(0, 0.0, 0.0,  1,  1),
#'   ts     = as.POSIXct("2024-01-01 00:00:00", tz="UTC") + c(0,60,120, 0, 90)
#' )
#'
#' seg <- pt_to_seg_trj(
#'   pts,
#'   cols = list(fl_id="flight", seq_id="seq", lon="lon", lat="lat", time_over="ts"),
#'   order_by = "seq_id",
#'   compute_distance = TRUE,
#'   compute_duration = TRUE
#' )
#' seg[]
#' }
#'
#' @importFrom data.table as.data.table copy setDT setnames shift .N .SD
#' @importFrom geosphere distHaversine
#' @export
pt_to_seg_trj <- function(
        trj_data,
        cols = list(
            fl_id    = "fl_id",
            seq_id   = NULL,
            lon      = "lon",
            lat      = "lat",
            altitude = "altitude",
            time_over= "time_over",
            adep     = "adep",
            ades     = "ades"
        ),
        order_by         = c("seq_id","time_over","none"),
        keep_cols        = NULL,
        drop_incomplete  = TRUE,
        compute_distance = FALSE,
        compute_duration = FALSE,
        make_segment_id  = TRUE
) {
    # --- deps & input ---
    if (!requireNamespace("data.table", quietly = TRUE)) {
        stop("pt_to_seg_trj(): package 'data.table' is required.")
    }
    order_by <- match.arg(order_by)
    
    dt <- data.table::as.data.table(data.table::copy(trj_data))
    
    # --- normalize mapping & validate ---
    # Allow NULL for optional columns in 'cols'.
    canonical <- c("fl_id","seq_id","lon","lat","altitude","time_over","adep","ades")
    if (!all(names(cols) %in% canonical)) {
        stop("pt_to_seg_trj(): 'cols' contains unknown keys. Allowed: ",
             paste(canonical, collapse=", "))
    }
    # required ones must be non-NULL and present in data
    required <- c("fl_id","lon","lat","time_over", "adep", "ades")
    missing_keys <- required[ vapply(required, function(k) is.null(cols[[k]]), logical(1)) ]
    if (length(missing_keys)) {
        stop("pt_to_seg_trj(): 'cols' must provide mappings for: ",
             paste(missing_keys, collapse=", "))
    }
    
    # Ensure mapped columns exist in dt
    mapped <- Filter(Negate(is.null), cols)
    missing_cols <- setdiff(unlist(mapped, use.names = FALSE), names(dt))
    if (length(missing_cols)) {
        stop("pt_to_seg_trj(): missing required columns in 'trj_data': ",
             paste(missing_cols, collapse = ", "))
    }
    
    # --- rename to canonical names on a copy (only if different) ---
    old <- unlist(mapped, use.names = FALSE)
    new <- names(mapped)
    idx <- old != new
    if (any(idx)) data.table::setnames(dt, old[idx], new[idx])
    
    # ensure time_over exists and is POSIXt
    if (is.null(cols$time_over) ||
        !"time_over" %in% names(dt)) {
        stop("pt_to_seg_trj(): 'time_over' mapping is required and must exist in data.")
    }
    if (!inherits(dt$time_over, "POSIXt")) {
        stop("pt_to_seg_trj(): 'time_over' must be POSIXct/POSIXlt.")
    }
    
    # if seq_id not provided, create a within-flight running index after ordering
    has_seq <- "seq_id" %in% names(dt)
    
    # --- order within flight if requested ---
    if (order_by == "time_over") {
        data.table::setorder(dt, fl_id, time_over)
    } else if (order_by == "seq_id") {
        if (!has_seq)
            stop("pt_to_seg_trj(): order_by='seq_id' requires a seq_id column or mapping.")
        if (is.character(dt$seq_id) &&
            suppressWarnings(!all(is.na(as.numeric(dt$seq_id))))) {
            dt[, seq_id := as.numeric(seq_id)]
        }
        data.table::setorder(dt, fl_id, seq_id)
    } else {
        # "none"
        data.table::setorder(dt, fl_id)
    }
    
    # create seq_id if it was absent (after final order is set)
    if (!has_seq)
        dt[, seq_id := seq_len(.N), by = fl_id]
    
    # --- build segments (lead of next point in each flight) ---
    # Compute entry (e_) from current row, exit (x_) from lead() within fl_id
    trj_seg <- data.table::copy(dt)[
        , `:=`(
            e_seq_id = seq_id,
            x_seq_id = data.table::shift(seq_id, type = "lead"),
            e_lon    = lon,
            x_lon    = data.table::shift(lon, type = "lead"),
            e_lat    = lat,
            x_lat    = data.table::shift(lat, type = "lead")
        ),
        by = fl_id
    ]
    
    # Optional fields
    if (!is.null(cols$altitude)) {
        trj_seg[, `:=`(
            e_alt = altitude,
            x_alt = data.table::shift(altitude, type = "lead")
        ), by = fl_id]
    }
    if (!is.null(cols$time_over)) {
        trj_seg[, `:=`(
            e_time = time_over,
            x_time = data.table::shift(time_over, type = "lead")
        ), by = fl_id]
    }
    if (!is.null(cols$adep)) trj_seg[, adep := adep]
    if (!is.null(cols$ades)) trj_seg[, ades := ades]
    
    # Drop incomplete last rows unless asked not to
    if (drop_incomplete) {
        trj_seg <- trj_seg[!is.na(x_lon) & !is.na(x_lat)]
    }
    
    # --- derived metrics ---
    if (compute_distance) {
        if (!requireNamespace("geosphere", quietly = TRUE)) {
            stop("pt_to_seg_trj(): set compute_distance=FALSE or install.packages('geosphere').")
        }
        # compute in two steps (avoid referencing a just-created column)
        trj_seg[, dist_m  := geosphere::distHaversine(
            cbind(e_lon, e_lat), 
            cbind(x_lon, x_lat))
        ][, dist_nm := dist_m / 1852]
    }
    if (compute_duration) {
        if (is.null(cols$time_over)) {
            warning("pt_to_seg_trj(): compute_duration=TRUE but 'time_over' not provided; skipping.")
        } else {
            trj_seg[, dur_s := as.numeric(x_time - e_time, units = "secs")]
        }
    }
    
    # --- segment id ---
    if (make_segment_id) {
        trj_seg[, seg_id := paste0(fl_id, ":", e_seq_id, ">", x_seq_id)]
    }
    
    # --- select & order columns for nice output ---
    # keep_cols are taken from the entry row (current row)
    extra_keep <- intersect(keep_cols %||% character(), names(dt))
    # helpers
    .opt <- function(x) intersect(x, names(trj_seg))
    
    out_cols <- c(
        "fl_id", "seg_id"[make_segment_id],
        "e_seq_id", "x_seq_id",
        .opt(c("adep","ades")),
        "e_lon","e_lat","x_lon","x_lat",
        .opt(c("e_alt","x_alt","e_time","x_time")),
        .opt(extra_keep),
        .opt(c("dist_m","dist_nm","dur_s"))
    )
    out_cols <- Filter(function(z) z %in% names(trj_seg), out_cols)
    
    data.table::setcolorder(trj_seg, out_cols)
    trj_seg[, ..out_cols]
}

# small internal helper (safe null-coalescing)
`%||%` <- function(x, y) if (is.null(x)) y else x
