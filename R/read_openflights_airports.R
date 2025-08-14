#' Read and normalize OpenFlights airports data (readr backend)
#'
#' @description
#' Reads the OpenFlights \code{airports.dat} file (URL or local path) using
#' \pkg{readr}, validates the schema, coerces column types, and normalizes
#' common quirks (e.g., \code{"\\N"} for missing values). Returns a
#' \code{data.table}.
#'
#' @param path Character. URL or file path to \code{airports.dat}.
#'   Defaults to the official GitHub raw URL.
#' @param check Logical. If \code{TRUE} (default), run basic validation
#'   checks (column count, id uniqueness, code formats) and warn on issues.
#'#' @param keep Character vector of column names to retain (after normalization).
#'   Default `NULL` keeps all. Unknown names are ignored with a warning.
#' @return A \code{data.table} with columns:
#' \itemize{
#'   \item \code{id} (integer), \code{name} (character), \code{city} (character),
#'   \item \code{country} (character), \code{iata_code} (character), \code{icao_code} (character),
#'   \item \code{latitude} (numeric), \code{longitude} (numeric), \code{altitude} (integer),
#'   \item \code{timezone_offset} (numeric), \code{dst_rule} (character),
#'   \item \code{timezone_region} (character), \code{type} (character), \code{source} (character)
#' }
#'
#' @examples
#' \dontrun{
#' airports <- read_openflights_airports()
#' airports[iata_code == "BRU"]
#' }
#'
#' @importFrom readr read_csv cols col_integer col_double col_character
#' @importFrom data.table as.data.table setnames
#' @export
read_openflights_airports <- function(
        path  = "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat",
        check = TRUE,
        keep = NULL
) {
    if (!requireNamespace("readr", quietly = TRUE)) {
        stop("Package 'readr' is required.")
    }
    if (!requireNamespace("data.table", quietly = TRUE)) {
        stop("Package 'data.table' is required.")
    }
    
    # Canonical column names (OpenFlights schema: 14 columns, no header)
    canon_names <- c(
        "id", "name", "city", "country", "iata_code", "icao_code",
        "latitude", "longitude", "altitude", "timezone_offset",
        "dst_rule", "timezone_region", "type", "source"
    )
    
    # readr schema: airports.dat is comma-separated, quoted, no header
    col_types <- readr::cols(
        # id, altitude as integer-ish; lat/lon/tz offset as double
        X1  = readr::col_integer(),
        X2  = readr::col_character(),
        X3  = readr::col_character(),
        X4  = readr::col_character(),
        X5  = readr::col_character(),
        X6  = readr::col_character(),
        X7  = readr::col_double(),
        X8  = readr::col_double(),
        X9  = readr::col_integer(),
        X10 = readr::col_double(),
        X11 = readr::col_character(),
        X12 = readr::col_character(),
        X13 = readr::col_character(),
        X14 = readr::col_character()
    )
    
    tbl <- readr::read_csv(
        file      = path,
        col_names = FALSE,
        col_types = col_types,
        na = c("\\N", ""),           # OpenFlights uses "\N" for NA
        progress = FALSE,
        quote = "\""
    )
    
    dt <- data.table::as.data.table(tbl)
    
    # Validate column count and rename
    if (ncol(dt) < length(canon_names)) {
        stop(
            "airports.dat has ", ncol(dt), " columns; expected ",
            length(canon_names), ". The file/schema may have changed."
        )
    }
    if (ncol(dt) > length(canon_names)) {
        warning("airports.dat has ", ncol(dt), " columns; truncating to first 14.")
        dt <- dt[, seq_len(length(canon_names))]
    }
    data.table::setnames(dt, canon_names)
    
    # Trim strings
    trim <- function(x) if (is.character(x)) trimws(x) else x
    chr_cols <- c("name","city","country","iata_code","icao_code",
                  "dst_rule","timezone_region","type","source")
    for (cc in chr_cols) {
        if (cc %in% names(dt)) dt[[cc]] <- trim(dt[[cc]])
    }
    
    # Uppercase codes
    if ("iata_code" %in% names(dt)) dt[!is.na(iata_code), iata_code := toupper(iata_code)]
    if ("icao_code" %in% names(dt)) dt[!is.na(icao_code), icao_code := toupper(icao_code)]
    
    # Optional checks
    if (isTRUE(check)) {
        if (anyDuplicated(dt$id)) {
            dup_n <- sum(duplicated(dt$id))
            warning("Duplicate 'id' values detected in airports data (n=", 
                    dup_n, ").")
        }
        bad_ll <- dt[is.na(latitude) | is.na(longitude) |
                         latitude < -90 | latitude > 90 |
                         longitude < -180 | longitude > 180, .N]
        if (bad_ll > 0) {
            warning("Found ", bad_ll, " rows with invalid or missing lat/lon.")
        }
        if ("iata_code" %in% names(dt)) {
            bad_iata <- dt[!is.na(iata_code) & !grepl("^[A-Z0-9]{3}$", 
                                                      iata_code), .N]
            if (bad_iata > 0) warning("Found ", bad_iata, " rows with non-standard IATA codes.")
        }
        if ("icao_code" %in% names(dt)) {
            bad_icao <- dt[!is.na(icao_code) & !grepl("^[A-Z0-9]{4}$", icao_code), unique(icao_code)]
            if (length(bad_icao) > 0) {
                warning(
                    "Found ", length(bad_icao),
                    " rows with non-standard ICAO codes: ",
                    paste(bad_icao, collapse = ", ")
                )
            }
        }
    }
    
    # Optional column selection
    if (!is.null(keep)) {
        unknown <- setdiff(keep, names(dt))
        if (length(unknown)) {
            warning("Ignoring unknown columns in `keep`: ", paste(unknown, collapse = ", "))
        }
        keep_ok <- intersect(keep, names(dt))
        if (length(keep_ok) == 0L) stop("No valid column names supplied in `keep`.")
        dt <- dt[, ..keep_ok]
    }
    
    dt[]
}
