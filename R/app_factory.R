create_usgs_lidar_app <- function(initial_aoi = NULL) {
  assert_packages()
  if (!is.null(initial_aoi)) initial_aoi <- normalize_aoi(initial_aoi)

  add_aoi_to_map <- function(map, x) {
    types <- unique(as.character(sf::st_geometry_type(x)))
    if (all(types %in% c("POINT", "MULTIPOINT"))) {
      leaflet::addCircleMarkers(
        map, data = x, radius = 7, color = "#c63c2f", weight = 3,
        fillColor = "#ffffff", fillOpacity = 0.9, group = "AOI"
      )
    } else {
      leaflet::addPolygons(
        map, data = x, color = "#c63c2f", weight = 3,
        fillOpacity = 0.05, group = "AOI"
      )
    }
  }

  fit_aoi <- function(map, x) {
    bbox <- sf::st_bbox(x)
    if (bbox[["xmin"]] == bbox[["xmax"]]) {
      bbox[c("xmin", "xmax")] <- bbox[["xmin"]] + c(-0.02, 0.02)
    }
    if (bbox[["ymin"]] == bbox[["ymax"]]) {
      bbox[c("ymin", "ymax")] <- bbox[["ymin"]] + c(-0.02, 0.02)
    }
    leaflet::fitBounds(map, bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
  }

  css <- "
    body { background: #f4f7f4; }
    .navbar-default { background: #173f35; border-color: #173f35; }
    .navbar-default .navbar-brand, .navbar-default .navbar-nav > li > a { color: white; }
    .well { background: white; border: 0; box-shadow: 0 2px 12px rgba(20,55,45,.09); }
    .btn-primary { background: #177245; border-color: #177245; }
    .btn-success { background: #b75b22; border-color: #b75b22; }
    .metric { display:inline-block; margin: 0 18px 8px 0; }
    .metric b { display:block; color:#173f35; font-size:1.35em; }
    .note { color:#5e6b65; font-size:.92em; }
    #map { border-radius: 8px; box-shadow: 0 2px 12px rgba(20,55,45,.12); }
  "

  ui <- shiny::navbarPage(
    title = "USGS 3DEP Lidar Explorer",
    header = shiny::tags$head(shiny::tags$style(shiny::HTML(css))),
    shiny::tabPanel(
      "Explore & download",
      shiny::fluidPage(
        shiny::br(),
        shiny::sidebarLayout(
          shiny::sidebarPanel(
            width = 4,
            shiny::h4("1. Area of interest"),
            shiny::fileInput(
              "aoi_file", "Load spatial file",
              accept = c(".rds", ".rda", ".RData", ".gpkg", ".geojson", ".json", ".kml", ".zip")
            ),
            shiny::helpText("Or pass an sf object with run_usgs_lidar_app(my_sf)."),
            shiny::actionButton("find_projects", "Find overlapping projects", class = "btn-primary"),
            shiny::hr(),
            shiny::h4("2. Projects"),
            shiny::uiOutput("project_picker"),
            shiny::actionButton("find_tiles", "Find tiles in selected projects", class = "btn-primary"),
            shiny::hr(),
            shiny::h4("3. Tiles and destination"),
            shiny::uiOutput("tile_picker"),
            shiny::fluidRow(
              shiny::column(9, shiny::textInput("destination", "Download folder", value = normalizePath(getwd(), winslash = "/"))),
              shiny::column(3, shiny::br(), shiny::actionButton("browse", "Browse"))
            ),
            shiny::fluidRow(
              shiny::column(6, shiny::numericInput("workers", "Parallel downloads", 4, min = 1, max = 16)),
              shiny::column(6, shiny::numericInput("retries", "Retries", 5, min = 1, max = 20))
            ),
            shiny::actionButton("download", "Download selected tiles", class = "btn-success"),
            shiny::actionButton("validate", "Validate downloaded LAS/LAZ"),
            shiny::br(), shiny::br(),
            shiny::uiOutput("status")
          ),
          shiny::mainPanel(
            width = 8,
            shiny::uiOutput("metrics"),
            leaflet::leafletOutput("map", height = "650px"),
            shiny::br(),
            shiny::tabsetPanel(
              shiny::tabPanel("Projects", shiny::tableOutput("project_table")),
              shiny::tabPanel("Tiles", shiny::tableOutput("tile_table")),
              shiny::tabPanel("Download results", shiny::tableOutput("download_table")),
              shiny::tabPanel("LAS/LAZ validation", shiny::tableOutput("validation_table"))
            )
          )
        )
      )
    ),
    shiny::tabPanel(
      "About & sources",
      shiny::fluidPage(
        shiny::br(),
        shiny::div(class = "well",
          shiny::h3("What this app does"),
          shiny::p("The app queries the USGS 3DEP lidar project index, preserves every overlapping project so you can choose among vintages, queries tile-level TNM products for the exact area of interest, and downloads selected LAS/LAZ files."),
          shiny::p("Downloads use partial files, resume when supported, retry transient failures, skip complete files, preserve the USGS LAZ/LAS subfolder, and record failed URLs."),
          shiny::h4("Authoritative references"),
          shiny::tags$ul(
            shiny::tags$li(shiny::tags$a(href = paste0(USGS_INDEX_ROOT, "/"), target = "_blank", "3DEP Elevation Index map service")),
            shiny::tags$li(shiny::tags$a(href = "https://apps.nationalmap.gov/lidar-explorer/#/", target = "_blank", "USGS Lidar Explorer")),
            shiny::tags$li(shiny::tags$a(href = "https://coast.noaa.gov/inventory/", target = "_blank", "NOAA Interagency Elevation Inventory")),
            shiny::tags$li(shiny::tags$a(href = "https://tnmaccess.nationalmap.gov/api/v1/", target = "_blank", "The National Map Access API"))
          ),
          shiny::p(class = "note", "This is a local downloader. The destination folder is on the computer running R/Shiny, not necessarily the web browser's computer.")
        )
      )
    )
  )

  server <- function(input, output, session) {
    aoi <- shiny::reactiveVal(initial_aoi)
    projects <- shiny::reactiveVal(NULL)
    tiles <- shiny::reactiveVal(NULL)
    download_results <- shiny::reactiveVal(NULL)
    validation <- shiny::reactiveVal(NULL)
    message <- shiny::reactiveVal(if (is.null(initial_aoi)) "Load an area of interest to begin." else "Area of interest supplied from R.")

    shiny::observeEvent(input$aoi_file, {
      tryCatch({
        loaded <- read_aoi_file(input$aoi_file$datapath, input$aoi_file$name)
        aoi(loaded); projects(NULL); tiles(NULL)
        message(paste("Loaded", input$aoi_file$name))
      }, error = function(e) message(paste("AOI error:", conditionMessage(e))))
    })

    output$map <- leaflet::renderLeaflet({
      map <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
        leaflet::addProviderTiles(leaflet::providers$Esri.NatGeoWorldMap, group = "Basemap") |>
        leaflet::addWMSTiles(
          baseUrl = paste0(USGS_INDEX_ROOT, "/WMSServer?"),
          layers = as.character(USGS_LIDAR_DISPLAY_LAYER),
          options = leaflet::WMSTileOptions(format = "image/png", transparent = TRUE),
          attribution = "USGS 3DEP", group = "USGS lidar availability"
        ) |>
        leaflet::addLayersControl(
          overlayGroups = c("USGS lidar availability", "AOI", "Projects", "Tiles"),
          options = leaflet::layersControlOptions(collapsed = FALSE)
        )
      if (!is.null(aoi())) {
        map <- fit_aoi(add_aoi_to_map(map, aoi()), aoi())
      }
      map
    })

    refresh_map <- function() {
      proxy <- leaflet::leafletProxy("map") |>
        leaflet::clearGroup("AOI") |>
        leaflet::clearGroup("Projects") |>
        leaflet::clearGroup("Tiles")
      if (!is.null(aoi())) {
        proxy <- add_aoi_to_map(proxy, aoi())
      }
      if (!is.null(projects()) && nrow(projects())) {
        proxy <- proxy |> leaflet::addPolygons(
          data = projects(), color = "#177245", weight = 2, fillColor = "#55a868", fillOpacity = 0.18,
          label = ~paste0(project, " — ", ql), group = "Projects"
        )
      }
      if (!is.null(tiles()) && nrow(tiles())) {
        proxy <- proxy |> leaflet::addPolygons(
          data = tiles(), color = "#b75b22", weight = 1, fillColor = "#e69f62", fillOpacity = 0.20,
          label = ~paste0(title, " (", size, ")"), group = "Tiles"
        )
      }
      invisible(proxy)
    }

    shiny::observeEvent(input$find_projects, {
      if (is.null(aoi())) { message("Load or supply an sf area of interest first."); return() }
      message("Querying the USGS 3DEP project index…")
      tryCatch({
        found <- shiny::withProgress(message = "Querying USGS projects", value = 0.4, query_usgs_projects(aoi()))
        projects(found); tiles(NULL)
        message(if (nrow(found)) paste("Found", nrow(found), "overlapping project(s).") else "No overlapping USGS lidar projects were found.")
        refresh_map()
      }, error = function(e) message(paste("Project query failed:", conditionMessage(e))))
    })

    output$project_picker <- shiny::renderUI({
      x <- projects()
      if (is.null(x) || !nrow(x)) return(shiny::helpText("No project results yet."))
      labels <- sprintf("%s | %s | %s to %s", x$project, x$ql, x$collect_start_display, x$collect_end_display)
      shiny::checkboxGroupInput("project_ids", "Choose one or more overlapping projects", choices = stats::setNames(x$project_key, labels), selected = x$project_key)
    })

    shiny::observeEvent(input$find_tiles, {
      x <- projects()
      selected <- input$project_ids
      if (is.null(x) || !length(selected)) { message("Select at least one project first."); return() }
      chosen <- x[x$project_key %in% selected, , drop = FALSE]
      message("Querying tile-level products from The National Map…")
      tryCatch({
        found <- shiny::withProgress(message = "Querying USGS lidar tiles", value = 0.4, query_tnm_tiles(aoi(), chosen))
        tiles(found)
        message(if (nrow(found)) paste("Found", nrow(found), "intersecting tile(s).") else "No tile records matched the selected project(s).")
        refresh_map()
      }, error = function(e) message(paste("Tile query failed:", conditionMessage(e))))
    })

    output$tile_picker <- shiny::renderUI({
      x <- tiles()
      if (is.null(x) || !nrow(x)) return(shiny::helpText("No tile results yet."))
      labels <- sprintf("%s | %s | %s", x$project, x$size, basename(x$download_url))
      shiny::selectizeInput(
        "tile_ids", "Choose tiles", choices = stats::setNames(x$tile_id, labels), selected = x$tile_id,
        multiple = TRUE, options = list(plugins = list("remove_button"), maxOptions = 20000)
      )
    })

    shiny::observeEvent(input$browse, {
      if (.Platform$OS.type != "windows") { message("Paste a destination path into the download-folder field."); return() }
      chosen <- utils::choose.dir(default = input$destination, caption = "Choose lidar download folder")
      if (!is.na(chosen)) shiny::updateTextInput(session, "destination", value = normalizePath(chosen, winslash = "/"))
    })

    shiny::observeEvent(input$download, {
      x <- tiles(); selected <- input$tile_ids
      if (is.null(x) || !length(selected)) { message("Select at least one tile to download."); return() }
      selected_tiles <- x[x$tile_id %in% selected, , drop = FALSE]
      selected_projects <- projects()[projects()$project %in% selected_tiles$project, , drop = FALSE]
      message(paste("Downloading", nrow(selected_tiles), "tile(s)…"))
      tryCatch({
        result <- shiny::withProgress(
          message = paste("Downloading", nrow(selected_tiles), "tile(s) in parallel"), value = 0.5,
          download_tiles(selected_tiles, selected_projects, input$destination, input$workers, input$retries)
        )
        download_results(result)
        counts <- table(factor(result$status, levels = c("downloaded", "skipped", "failed")))
        message(sprintf("Finished: %d downloaded, %d already complete, %d failed.", counts[[1]], counts[[2]], counts[[3]]))
      }, error = function(e) message(paste("Download failed:", conditionMessage(e))))
    })

    shiny::observeEvent(input$validate, {
      result <- download_results()
      if (is.null(result) || !nrow(result)) { message("Download tiles before running validation."); return() }
      message("Reading LAS/LAZ headers with rlas and building a lidR catalog…")
      tryCatch({
        checked <- shiny::withProgress(message = "Validating lidar files", value = 0.4, {
          catalog <- open_lidr_catalog(input$destination)
          attr(catalog, "source_folder") <- input$destination
          inspect_las_files(result$path)
        })
        validation(checked)
        message(paste("Validated", nrow(checked), "LAS/LAZ file(s) with rlas; lidR catalog opened successfully."))
      }, error = function(e) message(paste("Validation failed:", conditionMessage(e))))
    })

    output$status <- shiny::renderUI(shiny::div(class = "alert alert-info", message()))
    output$metrics <- shiny::renderUI({
      project_count <- if (is.null(projects())) 0L else nrow(projects())
      tile_count <- if (is.null(tiles())) 0L else nrow(tiles())
      total_size <- if (is.null(tiles()) || !nrow(tiles())) 0 else sum(tiles()$size_bytes, na.rm = TRUE)
      shiny::div(
        shiny::span(class = "metric", shiny::tags$b(project_count), "overlapping projects"),
        shiny::span(class = "metric", shiny::tags$b(tile_count), "intersecting tiles"),
        shiny::span(class = "metric", shiny::tags$b(format_bytes(total_size)), "available download")
      )
    })
    output$project_table <- shiny::renderTable({
      x <- projects(); if (is.null(x) || !nrow(x)) return(NULL)
      sf::st_drop_geometry(x)[, c("project", "workunit", "ql", "collect_start_display", "collect_end_display", "horiz_crs", "vert_crs", "geoid"), drop = FALSE]
    }, striped = TRUE, bordered = FALSE)
    output$tile_table <- shiny::renderTable({
      x <- tiles(); if (is.null(x) || !nrow(x)) return(NULL)
      head(sf::st_drop_geometry(x)[, c("project", "title", "format", "size", "publication_date", "manifest_verified"), drop = FALSE], 200)
    }, striped = TRUE, bordered = FALSE)
    output$download_table <- shiny::renderTable(download_results(), striped = TRUE, bordered = FALSE)
    output$validation_table <- shiny::renderTable(validation(), striped = TRUE, bordered = FALSE)
  }

  shiny::shinyApp(ui, server)
}
