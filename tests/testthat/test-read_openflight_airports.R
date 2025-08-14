test_that("read_openflights_airports reads a local airports.dat", {
    skip_on_cran()
    
    # create a tiny local file with the expected 14 columns (comma, quoted, no header)
    tmp <- tempfile(fileext = ".dat")
    lines <- c(
        '"1","Zzz Airport","Zzz City","Zed","ZZZ","ZZZZ","10.0","20.0","100","1.0","E","Etc/UTC","airport","OurSource"'
    )
    writeLines(lines, tmp, useBytes = TRUE)
    
    dt <- read_openflights_airports(path = tmp, check = TRUE, keep = c("icao_code","longitude","latitude"))
    expect_s3_class(dt, "data.table")
    expect_equal(names(dt), c("icao_code","longitude","latitude"))
    expect_equal(nrow(dt), 1L)
})
