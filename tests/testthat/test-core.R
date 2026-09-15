source(testthat::test_path("..", "..", "R", "utils.R"))
source(testthat::test_path("..", "..", "R", "aoi.R"))
source(testthat::test_path("..", "..", "R", "download.R"))

testthat::test_that("AOI normalization transforms to WGS84", {
  point <- sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_point(c(-112, 33)), crs = 4326))
  normalized <- normalize_aoi(sf::st_transform(point, 3857))
  testthat::expect_s3_class(normalized, "sf")
  testthat::expect_equal(sf::st_crs(normalized)$epsg, 4326)
})

testthat::test_that("USGS project-relative paths preserve subfolders", {
  root <- "https://rockyweb.usgs.gov/vdelivery/Datasets/Staged/Elevation/LPC/Projects/AZ_Test_B20/AZ_Test"
  url <- paste0(root, "/LAZ/USGS_LPC_AZ_Test_w0001n0001.laz")
  expected <- file.path("LAZ", "USGS_LPC_AZ_Test_w0001n0001.laz")
  testthat::expect_equal(relative_tile_path(url, root), expected)
})

testthat::test_that("unsafe destination names are sanitized", {
  testthat::expect_equal(safe_name("A:B/C*D"), "A_B_C_D")
})
