# Source this file to run the native example and define layered_data_stack().
# The lake/dbt workflow runs only when you call that function explicitly.
# Example:
# demo <- layered_data_stack(executable = "/path/to/dbt")
# demo$revenue
# Use backend = "ducklake" only with compatible R/Python engines and extension
# access. The optional catalog argument accepts catalog_openmetadata_dbt(...),
# a function receiving the dbt result, or a compatible custom metadata adapter.
library(tidyweave)

native_orders <- product(
  "orders",
  data.frame(order_id = 1:3, amount = c(25, 75, 50))
) |>
  add_quality(~ amount >= 0) |>
  run()
stopifnot(sum(collect(native_orders)$amount) == 150)

layered_data_stack <- function(
  path = tempfile("tidyweave-layered-"),
  backend = c("duckdb", "ducklake"),
  executable = "dbt",
  catalog = NULL,
  use_pointblank = FALSE
) {
  backend <- match.arg(backend)
  packages <- c("duckdb", "yaml", "processx")
  if (use_pointblank) {
    packages <- c(packages, "pointblank")
  }
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(
      "Install optional packages: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!file.exists(executable) && !nzchar(Sys.which(executable))) {
    stop(
      "Install dbt-duckdb separately and supply its dbt executable.",
      call. = FALSE
    )
  }
  if (
    dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))
  ) {
    stop("Choose a new or empty example directory.", call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  config <- lake_config(
    path = file.path(path, "lake"),
    layers = c("raw", "staging", "core", "marts"),
    backend = backend
  )
  orders <- data.frame(
    order_id = 1:3,
    customer_id = c(101L, 101L, 102L),
    amount = c(25, 75, 50)
  )
  quality_engine <- if (use_pointblank) "pointblank" else "native"
  definition <- product("orders", orders) |>
    add_quality(~ amount >= 0, engine = quality_engine)

  # Receipt is separate from acceptance. The rejected delivery stays in landing.
  accepted <- definition |> ingest(to = config)
  bad_orders <- orders
  bad_orders$amount[1] <- -25
  rejected <- definition |>
    add_source(bad_orders, replace = TRUE) |>
    ingest(to = config, stop_on_failure = FALSE)
  stopifnot(rejected$status == "blocked", sum(collect(accepted)$amount) == 150)

  # No live R connection remains open when the separate dbt process starts.
  project <- dbt_init(
    file.path(path, "analytics"),
    config,
    executable = executable,
    sources = list(orders = accepted)
  )
  built <- run(project, echo = FALSE, catalog = catalog)
  approved <- publish(built, "customer_revenue", to = config)
  initial_revenue <- collect(approved)
  stopifnot(sum(initial_revenue$revenue) == 150)

  # A correction binds another immutable RAW release under the same logical name.
  next_orders <- orders
  next_orders$amount[1] <- 50
  new_raw <- definition |>
    add_source(next_orders, replace = TRUE) |>
    ingest(to = config)
  project <- dbt_sources(project, list(orders = new_raw), name = "raw")
  rebuilt <- run(project, echo = FALSE, catalog = catalog)
  corrected <- publish(rebuilt, "customer_revenue", to = config)
  revenue <- collect(corrected)
  stopifnot(sum(revenue$revenue) == 175, sum(collect(approved)$revenue) == 150)

  # Consumers can use ordinary R data. Keep the release identity with the export.
  saveRDS(revenue, file.path(path, "approved-revenue.rds"))
  saveRDS(corrected$outputs, file.path(path, "approved-revenue-reference.rds"))
  exported <- NULL
  if (requireNamespace("arrow", quietly = TRUE)) {
    exported <- product("revenue_export", corrected) |>
      set_target(target_parquet(file.path(path, "approved-revenue.parquet"))) |>
      run()
  }
  list(
    path = path,
    config = config,
    accepted = accepted,
    rejected = rejected,
    project = project,
    built = built,
    approved = approved,
    new_raw = new_raw,
    rebuilt = rebuilt,
    corrected = corrected,
    initial_revenue = initial_revenue,
    revenue = revenue,
    exported = exported
  )
}
