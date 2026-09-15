# Run with: Rscript run_app.R
# Or from an R session with an existing sf object:
#   source("run_app.R")
#   run_usgs_lidar_app(my_sf)

run_usgs_lidar_app <- function(aoi = NULL, launch.browser = TRUE, ...) {
  old <- options(usgs.lidar.aoi = aoi)
  on.exit(options(old), add = TRUE)
  shiny::runApp(appDir = ".", launch.browser = launch.browser, ...)
}

if (sys.nframe() == 0L) {
  run_usgs_lidar_app()
}

