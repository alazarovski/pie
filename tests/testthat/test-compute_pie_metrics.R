test_that("compute_pie_metrics returns PIE and distances", {
    skip_on_cran()
    
    # minimal points
    pts <- data.table::data.table(
        fl_id     = c(1,1),
        seq_id    = c(1,2),
        lon       = c(4.48,4.50),
        lat       = c(50.90,51.00),
        time_over = as.POSIXct(c("2025-08-14 12:00:00","2025-08-14 12:02:00"), tz="UTC"),
        adep      = "EBBR",
        ades      = "LFPG"
    )
    
    # tiny airports table (mock)
    apt <- data.table::data.table(
        icao_code = c("EBBR","LFPG"),
        longitude = c(4.48444, 2.55),
        latitude  = c(50.90139, 49.0097)
    )
    
    seg <- compute_pie_metrics(
        pts,
        airports = apt,
        cols = list(
            fl_id="fl_id", seq_id="seq_id",
            lon="lon", lat="lat",
            time_over="time_over",
            adep="adep", ades="ades"
        ),
        order_by = "time_over",
        quiet = TRUE
    )
    
    expect_s3_class(seg, "data.table")
    expect_true(all(c("gc_along_track_dist","gc_cross_track_dist","seg_distance","pie") %in% names(seg)))
    expect_true(is.integer(seg$pie) | all(is.na(seg$pie)))
})
