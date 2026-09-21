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
    tw_product(name) |>
      tw_add_source(source, name = "orders") |>
      tw_add_quality(~ amount >= 0) |>
      tw_add_quality(tw_quality_reference(
        customers,
        c(customer_id = "id"),
        copy = TRUE
      )) |>
      tw_add_catalog(record, name = "local-record")
  }
  results <- list(
    core = tw_run(definition("orders", input), evidence = evidence)
  )
  source <- input
  if (requireNamespace("RSQLite", quietly = TRUE)) {
    database <- file.path(path, "orders.sqlite")
    connection <- function() DBI::dbConnect(RSQLite::SQLite(), database)
    results$database <- definition("orders.database", source) |>
      tw_set_target(tw_target_database(connection, "orders")) |>
      tw_run(evidence = evidence)
    source <- tw_source_database(connection, table = "orders")
    stopifnot(sum(tw_read_source(source)$amount) == 150)
  }
  if (requireNamespace("arrow", quietly = TRUE)) {
    parquet <- file.path(path, "orders.parquet")
    results$parquet <- definition("orders.parquet", source) |>
      tw_set_target(tw_target_parquet(parquet)) |>
      tw_run(evidence = evidence)
    source <- tw_source_parquet(parquet)
    stopifnot(sum(tw_collect(tw_read_source(source))$amount) == 150)
  }
  if (requireNamespace("pins", quietly = TRUE)) {
    board <- pins::board_folder(file.path(path, "pins"), versioned = TRUE)
    results$pin <- definition("orders.pin", source) |>
      tw_set_target(tw_target_pins(board, "orders")) |>
      tw_run(evidence = evidence)
    pinned <- tw_source_pins(
      board,
      "orders",
      version = results$pin$outputs$version
    )
    stopifnot(sum(tw_read_source(pinned)$amount) == 150)
  }
  stopifnot(
    length(metadata) == length(results),
    nrow(tw_run_history(evidence)) == length(results),
    nrow(tw_incidents(evidence)) == 0L
  )
  list(
    path = path,
    results = results,
    history = tw_run_history(evidence),
    metadata = metadata
  )
}

advanced_result <- advanced_integrations()
print(advanced_result$history)
