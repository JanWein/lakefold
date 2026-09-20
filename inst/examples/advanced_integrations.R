# Run with source(system.file("examples", "advanced_integrations.R",
#   package = "tidyweave")). Optional components are skipped when not installed.
library(tidyweave)

advanced_integrations <- function(path = tempfile("tidyweave-advanced-")) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  evidence <- file.path(path, "runs")
  input <- data.frame(
    id = 1:3,
    customer_id = c(10L, 10L, 20L),
    amount = c(25, 75, 50)
  )
  customers <- data.frame(id = c(10L, 20L))
  metadata <- list()
  record <- function(value) {
    metadata[[length(metadata) + 1L]] <<- value
  }
  definition <- function(name, source) {
    product(name) |>
      add_source(source, name = "orders") |>
      add_quality(~ amount >= 0) |>
      add_quality(quality_reference(
        customers,
        c(customer_id = "id"),
        copy = TRUE
      )) |>
      add_catalog(record, name = "local-record")
  }
  results <- list(core = run(definition("orders", input), evidence = evidence))
  source <- input
  if (requireNamespace("RSQLite", quietly = TRUE)) {
    database <- file.path(path, "orders.sqlite")
    connection <- function() DBI::dbConnect(RSQLite::SQLite(), database)
    results$database <- definition("orders.database", source) |>
      set_target(target_database(connection, "orders")) |>
      run(evidence = evidence)
    source <- source_database(connection, table = "orders")
    stopifnot(sum(read_source(source)$amount) == 150)
  }
  if (requireNamespace("arrow", quietly = TRUE)) {
    parquet <- file.path(path, "orders.parquet")
    results$parquet <- definition("orders.parquet", source) |>
      set_target(target_parquet(parquet)) |>
      run(evidence = evidence)
    source <- source_parquet(parquet)
    stopifnot(sum(collect(read_source(source))$amount) == 150)
  }
  if (requireNamespace("pins", quietly = TRUE)) {
    board <- pins::board_folder(file.path(path, "pins"), versioned = TRUE)
    results$pin <- definition("orders.pin", source) |>
      set_target(target_pins(board, "orders")) |>
      run(evidence = evidence)
    pinned <- source_pins(
      board,
      "orders",
      version = results$pin$outputs$version
    )
    stopifnot(sum(read_source(pinned)$amount) == 150)
  }
  stopifnot(
    length(metadata) == length(results),
    nrow(run_history(evidence)) == length(results),
    nrow(incidents(evidence)) == 0L
  )
  list(
    path = path,
    results = results,
    history = run_history(evidence),
    metadata = metadata
  )
}

advanced_result <- advanced_integrations()
print(advanced_result$history)
