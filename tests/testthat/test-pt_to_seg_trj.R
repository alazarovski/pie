test_that("pt_to_seg_trj builds segments per flight", {
    skip_on_cran()
    
    pts <- data.table::data.table(
        fl_id     = c(1,1,1, 2,2),
        seq_id    = c(1,2,3, 1,2),
        lon       = c(0, 0.5, 1.0, 0, 1),
        lat       = c(0, 0,   0,   1, 1),
        time_over = as.POSIXct("2025-01-01 00:00:00", tz="UTC") + c(0,60,120, 0, 90),
        adep      = c("EBBR","EBBR","EBBR","EBBR","EBBR"),
        ades      = c("LFPG","LFPG","LFPG","LFPG","LFPG")
    )
    
    seg <- pt_to_seg_trj(
        pts,
        cols = list(fl_id="fl_id", seq_id="seq_id", lon="lon", lat="lat", time_over="time_over", adep="adep", ades="ades"),
        order_by = "seq_id",
        compute_distance = TRUE,
        compute_duration = TRUE
    )
    
    expect_s3_class(seg, "data.table")
    expect_true(all(c("fl_id","e_seq_id","x_seq_id","e_lon","e_lat","x_lon","x_lat") %in% names(seg)))
    # n segments = sum(n_i - 1) over flights: (3-1) + (2-1) = 3
    expect_equal(nrow(seg), 3L)
})
