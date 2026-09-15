# Run with: Rscript run_app.R
# Or from an R session with an existing sf object:
#   source("path/to/run_app.R")
#   run_usgs_lidar_app(my_sf)

.run_app_source <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.run_app_args <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
.run_app_file <- if (!is.null(.run_app_source)) {
  .run_app_source
} else if (length(.run_app_args)) {
  sub("^--file=", "", .run_app_args[[1L]])
} else {
  file.path(getwd(), "run_app.R")
}
.usgs_lidar_project_dir <- dirname(normalizePath(.run_app_file, winslash = "/", mustWork = TRUE))

run_usgs_lidar_app <- function(aoi = NULL, launch.browser = TRUE, ...) {
  old <- options(usgs.lidar.aoi = aoi)
  on.exit(options(old), add = TRUE)
  shiny::runApp(appDir = .usgs_lidar_project_dir, launch.browser = launch.browser, ...)
}

if (sys.nframe() == 0L) {
  run_usgs_lidar_app()
}
