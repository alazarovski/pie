#' Compute PIE (Path Inefficiency) metrics from trajectory points
#'
#' @description
#' Takes raw trajectory points for one or more flights, converts them into
#' segments, enriches them with departure and arrival airport coordinates
#' from the OpenFlights dataset, and computes great-circle along-track and
#' cross-track distances, segment distances, and the PIE indicator.
#'
#' @param trj_pt A `data.table` or `data.frame` of trajectory points containing
#'   at least:
#'   \itemize{
#'     \item \code{fl_id} – flight identifier
#'     \item \code{seq_id} – point sequence number per flight
#'     \item \code{lon}, \code{lat} – point coordinates in decimal degrees
#'     \item \code{adep}, \code{ades} – ICAO codes of departure and arrival airports
#'   }
#'   Additional columns for altitude or timestamps are optional.
#'
#' @details
#' The function:
#' \enumerate{
#'   \item Reads OpenFlights airport data (only \code{icao_code}, \code{longitude},
#'         and \code{latitude} columns).
#'   \item Converts trajectory points into ordered segments using \code{\link{pt_to_seg_trj}}.
#'   \item Joins airport coordinates for \code{adep} and \code{ades}.
#'   \item Computes:
#'         \itemize{
#'           \item \code{gc_along_track_dist} – along-track distance along the great circle.
#'           \item \code{gc_cross_track_dist} – perpendicular distance from the great circle.
#'           \item \code{seg_distance} – Haversine distance for the segment.
#'         }
#'   \item Calculates the PIE metric as:
#'         \deqn{PIE = 100 \times \frac{gc\_cross\_track\_dist}{gc\_along\_track\_dist}}
#' }
#'
#' @return A `data.table` of trajectory segments with computed metrics,
#'   including the \code{pie} column (rounded to nearest integer).
#'
#' @seealso \code{\link{read_openflights_airports}}, \code{\link{pt_to_seg_trj}}
#'
#' @examples
#' \dontrun{
#' Example trajectory points with altitude and timestamps
#' 
#' trj_pts <- data.table::data.table(
#'   fl_id     = c(1, 1, 1),
#'   seq_id    = 1:3,
#'   lon       = c(4.484, 4.500, 4.520),
#'   lat       = c(50.900, 51.000, 51.100),
#'   altitude  = c(0, 1500, 3000),  # in feet
#'   time_over = as.POSIXct(
#'                  c("2025-08-14 12:00:00",
#'                    "2025-08-14 12:02:00",
#'                    "2025-08-14 12:04:00"),
#'                  tz = "UTC"
#'                ),
#'   adep      = "EBBR",
#'   ades      = "LFPG"
#' )
#'
#' # Compute PIE metrics
#' compute_pie_metrics(
#'   trj_pts,
#'   cols = list(
#'     fl_id     = "fl_id",
#'     seq_id    = "seq_id",
#'     lon       = "lon",
#'     lat       = "lat",
#'     altitude  = "altitude",
#'     time_over = "time_over",
#'     adep      = "adep",
#'     ades      = "ades"
#'   ),
#'   order_by = "time_over"
#' )
#' compute_pie_metrics(trj_pts)
#'
#' } 
#' @importFrom data.table data.table :=
#' @importFrom geosphere alongTrackDistance dist2gc distHaversine
#' @export

compute_pie_metrics <- function(
        trj_pt, airports = NULL, # optionally pass a preloaded airports DT
        cols = list(
            # mapping for pt_to_seg_trj
            fl_id     = "fl_id",
            seq_id    = NULL,
            # optional
            lon       = "lon",
            lat       = "lat",
            altitude  = NULL,
            time_over = "time_over",
            # required
            adep      = "adep",
            ades      = "ades"
        ), 
        order_by = c("flid", "time_over"), 
        quiet = TRUE) {
    
    
    # deps
    if (!requireNamespace("data.table", 
                          quietly = TRUE)) stop("Package 'data.table' is required.")
    if (!requireNamespace("geosphere", 
                          quietly = TRUE)) stop("Package 'geosphere' is required.")
    
    DT <- data.table::as.data.table(trj_pt)
    
    # basic input checks
    req_cols <- unlist(cols[c("fl_id", "lon", "lat", "time_over")], 
                       use.names = FALSE)
    if (anyNA(req_cols) ||
        any(!nzchar(req_cols)))
        stop("cols mapping must include non-empty fl_id, lon, lat, time_over."
        )
    missing_in <- setdiff(na.omit(req_cols), names(DT))
    if (length(missing_in))
        stop("Input trajectory is missing required columns: ",
             paste(missing_in, collapse = ", "))
    
    # build segments
    trj_seg <- pt_to_seg_trj(
        DT, 
        cols = cols, 
        order_by = order_by, 
        compute_distance = TRUE
    )
    trj_seg <- data.table::as.data.table(trj_seg)
    
    # ensure expected segment columns exist
    seg_needed <- c("e_lon","e_lat","x_lon","x_lat","adep","ades")
    seg_missing <- setdiff(seg_needed, names(trj_seg))
    if (length(seg_missing)) {
        stop("pt_to_seg_trj did not produce required columns: ", 
             paste(seg_missing, collapse = ", "))
    }
    
    # airports data (load or use provided)
    apt <- if (is.null(airports)) {
        read_openflights_airports(keep = c("icao_code","longitude","latitude"))
    } else {
        data.table::as.data.table(airports)[, .(icao_code, longitude, latitude)]
    }
    
    # guard airports columns
    if (!all(c("icao_code","longitude","latitude") %in% names(apt))) {
        stop("`airports` must contain columns: icao_code, longitude, latitude.")
    }
    
    # normalize ICAO codes upper/trim and key for fast joins
    apt[, icao_code := toupper(trimws(icao_code))]
    data.table::setkeyv(apt, "icao_code")
    
    # normalize adep/ades in trj_seg
    trj_seg[, `:=`(adep = toupper(trimws(adep)), ades = toupper(trimws(ades)))]
    
    # join airport coords
    trj_seg[
        apt
        , on = .(adep = icao_code)
        , `:=`(lon_adep = i.longitude, 
               lat_adep = i.latitude)
    ][
        apt
        , on = .(ades = icao_code)
        , `:=`(lon_ades = i.longitude, lat_ades = i.latitude)
    ]
    
    # warn if any airports missing
    miss_adep <- trj_seg[is.na(lon_adep) | is.na(lat_adep), data.table::uniqueN(adep)]
    miss_ades <- trj_seg[is.na(lon_ades) | is.na(lat_ades), data.table::uniqueN(ades)]
    if (!quiet && (miss_adep > 0 || miss_ades > 0)) {
        warning("Missing airport coords — unique adep missing: ", miss_adep,
                "; unique ades missing: ", miss_ades, ".")
    }
    
    # compute metrics (vectorized). Use absolute cross-track; guard zero/NA along-track.
    trj_seg[, `:=`(
        gc_along_track_dist = geosphere::alongTrackDistance(
            cbind(e_lon, e_lat),
            cbind(lon_ades, lat_ades),
            cbind(x_lon, x_lat)
        ),
        gc_cross_track_dist = geosphere::dist2gc(
            cbind(e_lon, e_lat),
            cbind(lon_ades, lat_ades),
            cbind(x_lon, x_lat)
        ),
        seg_distance = geosphere::distHaversine(
            cbind(e_lon, e_lat), cbind(x_lon, x_lat)
        )
    )]
    
    # PIE: handle zero/neg/NA along-track; return integer; keep NA where undefined
    trj_seg[, pie := {
        den <- gc_along_track_dist
        num <- abs(gc_cross_track_dist)
        out <- rep(NA_integer_, .N)
        ok <- is.finite(den) & den > 0 & is.finite(num)
        out[ok] <- as.integer(round(100 * num[ok] / den[ok], 0))
        out
    }]
    
    # optional: set a stable key for downstream joins
    if (all(c("fl_id","e_seq_id") %in% names(trj_seg))) {
                data.table::setkeyv(trj_seg, c("fl_id","e_seq_id"))
            }
    
    trj_seg[]
}

