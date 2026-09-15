# USGS 3DEP Lidar Explorer/Downloader

A local Shiny app that accepts an `sf` point, polygon, or multipolygon (or a file; see below); finds every overlapping USGS 3DEP lidar project; lets the user choose among overlapping projects and individual LAS/LAZ tiles; and downloads those tiles to a chosen folder.

The project polygons come from layer 24 (`Lidar Point Cloud`) of the USGS `3DEPElevationIndex` map service. Tile records and bounding boxes come from the official TNM Access products API, then tile URLs are checked against each project's `0_file_download_links.txt` manifest when it is available. The map also displays layer 8 of the index as the USGS availability overlay.

## Start the app

From this folder in R:

```r
source("run_app.R")
run_usgs_lidar_app()
```

Or at a command prompt:

```text
Rscript run_app.R
```

The required packages are `shiny`, `sf`, `leaflet`, `curl`, `jsonlite`, `rlas`, and `lidR`.

```r
install.packages(c("shiny", "sf", "leaflet", "curl", "jsonlite", "rlas", "lidR"))
```

## Start with an existing sf object

```r
library(sf)

my_aoi <- st_read("my_aoi.gpkg")
source("run_app.R")
run_usgs_lidar_app(my_aoi)
```

The app also accepts RDS/RData, GeoPackage, GeoJSON, KML, and zipped shapefile uploads. The object must have a valid CRS. Points and polygons are supported.

## Download behavior

- All overlapping lidar projects remain separate so users can choose one or several vintages.
- Only tile bounding boxes that intersect the exact `sf` geometry are retained.
- Tile URLs are cross-checked against the selected USGS project download manifests when those manifests are available.
- Selected tiles are written under `<destination>/<project>/LAZ/` (or the corresponding USGS subfolder).
- Existing files with the expected byte size are skipped.
- Incomplete downloads use `.part` files and resume when the server supports byte ranges.
- Downloads retry with backoff and can run in parallel.
- `selected_download_links.txt` records the requested URLs; failures are written to `failed_downloads.csv`.
- Validation reads each downloaded header with `rlas` and opens the destination as a `lidR` catalog without loading all points into memory.

## Authoritative sources

- [USGS 3DEP Elevation Index map service](https://index.nationalmap.gov/arcgis/rest/services/3DEPElevationIndex/MapServer/)
- [USGS Lidar Explorer](https://apps.nationalmap.gov/lidar-explorer/#/)
- [The National Map Access API](https://tnmaccess.nationalmap.gov/api/v1/)
- [NOAA Interagency Elevation Inventory](https://coast.noaa.gov/inventory/)

The destination is on the computer running the R process. A remotely hosted Shiny deployment cannot write directly to a visitor's arbitrary local folder.
