# USGSlazDownloader

USGSlazDownloader is a local **R Shiny** application for discovering, comparing, and downloading **USGS 3DEP lidar** data for a user-defined area of interest (AOI).

## What the app does

Users can provide an AOI as:
- An existing `sf` object in R, or
- An uploaded spatial file (`.gpkg`, `.geojson`, `.kml`, `.rds`/`.RData`, or zipped shapefile)

The app then:
- Displays the AOI on an Esri National Geographic basemap with the USGS lidar availability layer
- Queries the `3DEPElevationIndex` map service
- Identifies every overlapping lidar project (including multiple collections/years for the same location)

After one or more projects are selected, the app:
- Finds LAS/LAZ tiles intersecting the exact AOI
- Retrieves tile metadata from The National Map API
- Verifies tile URLs against each project's `0_file_download_links.txt` manifest
- Shows project footprints and tile boundaries on the map
- Allows selection of individual tiles and destination folder
- Downloads files concurrently with retries and partial-download resume
- Skips files that are already complete
- Preserves original USGS project and LAS/LAZ folder structure
- Records selected links and failed downloads for auditing/recovery
- Validates downloaded files with `rlas` and opens them as a `lidR` catalog

## Technology stack

- `shiny` for the user interface
- `leaflet` for map display and interaction
- `sf` for spatial operations
- `curl` and `jsonlite` for web service/API access
- `rlas` and `lidR` for lidar validation and catalog workflows

## Runtime model

This application is intended to run **locally** so it can write directly to user-selected directories, including mapped drives and network locations.