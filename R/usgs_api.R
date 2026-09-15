USGS_INDEX_ROOT <- "https://index.nationalmap.gov/arcgis/rest/services/3DEPElevationIndex/MapServer"
USGS_LIDAR_QUERY_LAYER <- 24L
USGS_LIDAR_DISPLAY_LAYER <- 8L
TNM_PRODUCTS_URL <- "https://tnmaccess.nationalmap.gov/api/v1/products"

geojson_to_sf <- function(text) {
  path <- tempfile(fileext = ".geojson")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(enc2utf8(text)), path)
  sf::st_read(path, quiet = TRUE, stringsAsFactors = FALSE)
}

query_usgs_projects <- function(aoi) {
  aoi <- normalize_aoi(aoi)
  endpoint <- sprintf("%s/%d/query", USGS_INDEX_ROOT, USGS_LIDAR_QUERY_LAYER)
  common <- list(
    where = "1=1",
    geometry = aoi_bbox_string(aoi),
    geometryType = "esriGeometryEnvelope",
    inSR = "4326",
    spatialRel = "esriSpatialRelIntersects"
  )

  ids_text <- http_request(
    endpoint,
    c(common, list(returnIdsOnly = "true", f = "json")),
    method = "POST"
  )
  ids <- unlist(read_json_response(ids_text)$objectIds %||% list(), use.names = FALSE)
  if (!length(ids)) return(sf::st_sf(geometry = sf::st_sfc(crs = 4326)))

  chunks <- split(ids, ceiling(seq_along(ids) / 200))
  pieces <- lapply(chunks, function(chunk) {
    geojson_to_sf(http_request(
      endpoint,
      list(
        objectIds = paste(chunk, collapse = ","),
        outFields = paste(c(
          "OBJECTID", "workunit", "workunit_id", "project", "project_id", "ql",
          "spec", "p_method", "collect_start", "collect_end", "lpc_pub_date",
          "lpc_link", "metadata_link", "horiz_crs", "vert_crs", "geoid"
        ), collapse = ","),
        returnGeometry = "true",
        outSR = "4326",
        f = "geojson"
      ),
      method = "POST"
    ))
  })
  raw <- do.call(rbind, pieces)
  raw <- raw[lengths(sf::st_intersects(raw, aoi)) > 0L, , drop = FALSE]
  if (!nrow(raw)) return(raw)

  raw$project <- as.character(raw$project)
  raw$lpc_link <- sub("/+$", "", as.character(raw$lpc_link))
  raw$project_key <- paste(raw$project, raw$lpc_link, sep = "||")
  groups <- split(seq_len(nrow(raw)), raw$project_key)

  rows <- lapply(seq_along(groups), function(i) {
    idx <- groups[[i]]
    first <- raw[idx[[1L]], , drop = FALSE]
    first$project_key <- as.character(i)
    first$workunit <- paste(sort(unique(na.omit(raw$workunit[idx]))), collapse = "; ")
    first$ql <- paste(sort(unique(na.omit(raw$ql[idx]))), collapse = ", ")
    first$geometry <- sf::st_union(sf::st_geometry(raw[idx, , drop = FALSE]))
    first
  })
  projects <- do.call(rbind, rows)
  projects$collect_start_display <- vapply(projects$collect_start, format_arcgis_date, character(1))
  projects$collect_end_display <- vapply(projects$collect_end, format_arcgis_date, character(1))
  projects
}

tnm_item_row <- function(item) {
  url <- item$downloadLazURL %||% item$downloadURL %||% ""
  data.frame(
    source_id = as.character(item$sourceId %||% ""),
    title = as.character(item$title %||% basename(url)),
    format = as.character(item$format %||% tools::file_ext(url)),
    size_bytes = as.numeric(item$sizeInBytes %||% NA_real_),
    publication_date = as.character(item$publicationDate %||% NA_character_),
    download_url = as.character(url),
    metadata_url = as.character(item$metaUrl %||% ""),
    preview_url = as.character(item$previewGraphicURL %||% ""),
    stringsAsFactors = FALSE
  )
}

read_project_download_manifest <- function(project_link) {
  project_link <- sub("/+$", "", as.character(project_link))
  if (!nzchar(project_link) || is.na(project_link)) return(character())
  text <- http_request(
    paste0(project_link, "/0_file_download_links.txt"),
    method = "GET",
    retries = 3L
  )
  lines <- trimws(strsplit(text, "\\r?\\n")[[1L]])
  unique(lines[nzchar(lines) & grepl("^https?://", lines, ignore.case = TRUE)])
}

query_tnm_tiles <- function(aoi, projects, page_size = 500L, max_tiles = 20000L) {
  aoi <- normalize_aoi(aoi)
  if (!nrow(projects)) stop("Select at least one project.", call. = FALSE)
  bbox <- aoi_bbox_string(aoi)
  offset <- 0L
  items <- list()
  total <- Inf

  while (offset < total && length(items) < max_tiles) {
    text <- http_request(
      TNM_PRODUCTS_URL,
      list(
        datasets = "Lidar Point Cloud (LPC)",
        bbox = bbox,
        max = page_size,
        offset = offset,
        outputFormat = "JSON"
      ),
      method = "GET"
    )
    page <- read_json_response(text)
    total <- as.integer(page$total %||% 0L)
    page_items <- page$items %||% list()
    if (!length(page_items)) break
    items <- c(items, page_items)
    offset <- offset + length(page_items)
  }

  if (!length(items)) {
    return(sf::st_sf(
      tile_id = character(), download_url = character(),
      geometry = sf::st_sfc(crs = 4326)
    ))
  }

  project_links <- unique(sub("/+$", "", as.character(projects$lpc_link)))
  project_links <- project_links[nzchar(project_links) & !is.na(project_links)]
  urls <- vapply(items, function(item) as.character(item$downloadLazURL %||% item$downloadURL %||% ""), character(1))
  in_project <- if (length(project_links)) {
    vapply(urls, function(url) any(startsWith(tolower(url), paste0(tolower(project_links), "/"))), logical(1))
  } else {
    rep(TRUE, length(urls))
  }

  items <- items[in_project & nzchar(urls)]
  if (!length(items)) {
    return(sf::st_sf(
      tile_id = character(), download_url = character(),
      geometry = sf::st_sfc(crs = 4326)
    ))
  }

  rows <- do.call(rbind, lapply(items, tnm_item_row))
  tiles <- sf::st_sf(rows, geometry = bounding_boxes_to_sf(items))
  tiles <- tiles[lengths(sf::st_intersects(tiles, aoi)) > 0L, , drop = FALSE]
  tiles <- tiles[!duplicated(tiles$download_url), , drop = FALSE]

  # The PowerShell workflow uses each project's authoritative USGS text manifest.
  # TNM supplies tile footprints; the manifest confirms that selected URLs still
  # belong to the staged project. A missing legacy manifest does not hide valid
  # TNM results.
  manifests <- lapply(project_links, function(link) {
    tryCatch(read_project_download_manifest(link), error = function(e) character())
  })
  manifest_urls <- unique(unlist(manifests, use.names = FALSE))
  tiles$manifest_verified <- if (length(manifest_urls)) {
    tolower(tiles$download_url) %in% tolower(manifest_urls)
  } else {
    NA
  }
  if (length(manifest_urls) && any(tiles$manifest_verified)) {
    tiles <- tiles[tiles$manifest_verified, , drop = FALSE]
  }
  tiles$tile_id <- as.character(seq_len(nrow(tiles)))

  links <- sub("/+$", "", as.character(projects$lpc_link))
  names(links) <- as.character(projects$project)
  tiles$project <- vapply(tiles$download_url, function(url) {
    hits <- names(links)[vapply(links, function(link) nzchar(link) && startsWith(tolower(url), paste0(tolower(link), "/")), logical(1))]
    if (length(hits)) hits[[1L]] else "Unknown project"
  }, character(1))
  tiles$size <- vapply(tiles$size_bytes, format_bytes, character(1))
  tiles
}
