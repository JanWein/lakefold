# Run with source(system.file("examples", "advanced_integrations.R",
#   package = "dataraft")). Optional components are skipped when not installed.
library(dataraft)

advanced_integrations <- function(path = tempfile("dataraft-advanced-")) {
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
    dr_product(name) |>
      dr_add_source(source, name = "orders") |>
      dr_add_quality(~ amount >= 0) |>
      dr_add_quality(dr_quality_reference(
        customers,
        c(customer_id = "id"),
        copy = TRUE
      )) |>
      dr_add_catalog(record, name = "local-record")
  }
  results <- list(
    core = dr_run(definition("orders", input), evidence = evidence)
  )
  source <- input
  if (requireNamespace("RSQLite", quietly = TRUE)) {
    database <- file.path(path, "orders.sqlite")
    connection <- function() DBI::dbConnect(RSQLite::SQLite(), database)
    results$database <- definition("orders.database", source) |>
      dr_set_target(dr_target_database(connection, "orders")) |>
      dr_run(evidence = evidence)
    source <- dr_source_database(connection, table = "orders")
    stopifnot(sum(dr_read_source(source)$amount) == 150)
  }
  if (requireNamespace("arrow", quietly = TRUE)) {
    parquet <- file.path(path, "orders.parquet")
    results$parquet <- definition("orders.parquet", source) |>
      dr_set_target(dr_target_parquet(parquet)) |>
      dr_run(evidence = evidence)
    source <- dr_source_parquet(parquet)
    stopifnot(sum(dr_collect(dr_read_source(source))$amount) == 150)
  }
  if (requireNamespace("pins", quietly = TRUE)) {
    board <- pins::board_folder(file.path(path, "pins"), versioned = TRUE)
    results$pin <- definition("orders.pin", source) |>
      dr_set_target(dr_target_pins(board, "orders")) |>
      dr_run(evidence = evidence)
    pinned <- dr_source_pins(
      board,
      "orders",
      version = results$pin$outputs$version
    )
    stopifnot(sum(dr_read_source(pinned)$amount) == 150)
  }
  stopifnot(
    length(metadata) == length(results),
    nrow(dr_run_history(evidence)) == length(results),
    nrow(dr_incidents(evidence)) == 0L
  )
  list(
    path = path,
    results = results,
    history = dr_run_history(evidence),
    metadata = metadata
  )
}

advanced_result <- advanced_integrations()
print(advanced_result$history)
