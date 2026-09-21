# Source this file to run the native example and define layered_data_stack().
# The lake/dbt workflow runs only when you call that function explicitly.
# Example:
# demo <- layered_data_stack(executable = "/path/to/dbt")
# demo$revenue
# Use backend = "ducklake" only with compatible R/Python engines and extension
# access. The optional catalog argument accepts tw_catalog_openmetadata_dbt(...),
# a function receiving the dbt result, or a compatible custom metadata adapter.
library(tidyweave)

native_orders <- tw_product(
  "orders",
  data.frame(order_id = 1:3, amount = c(25, 75, 50))
) |>
  tw_add_quality(~ amount >= 0) |>
  tw_run()
stopifnot(sum(tw_collect(native_orders)$amount) == 150)

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
  config <- tw_lake_config(
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
  definition <- tw_product("orders", orders) |>
    tw_add_quality(~ amount >= 0, engine = quality_engine)

  # Receipt is separate from acceptance. The rejected delivery stays in landing.
  accepted <- definition |> tw_ingest(to = config)
  bad_orders <- orders
  bad_orders$amount[1] <- -25
  rejected <- definition |>
    tw_add_source(bad_orders, replace = TRUE) |>
    tw_ingest(to = config, stop_on_failure = FALSE)
  stopifnot(
    rejected$status == "blocked",
    sum(tw_collect(accepted)$amount) == 150
  )

  # No live R connection remains open when the separate dbt process starts.
  project <- tw_dbt_init(
    file.path(path, "analytics"),
    config,
    executable = executable,
    sources = list(orders = accepted)
  )
  built <- tw_run(project, echo = FALSE, catalog = catalog)
  approved <- tw_publish(built, "customer_revenue", to = config)
  initial_revenue <- tw_collect(approved)
  stopifnot(sum(initial_revenue$revenue) == 150)

  # A correction binds another immutable RAW release under the same logical name.
  next_orders <- orders
  next_orders$amount[1] <- 50
  new_raw <- definition |>
    tw_add_source(next_orders, replace = TRUE) |>
    tw_ingest(to = config)
  project <- tw_dbt_sources(project, list(orders = new_raw), name = "raw")
  rebuilt <- tw_run(project, echo = FALSE, catalog = catalog)
  corrected <- tw_publish(rebuilt, "customer_revenue", to = config)
  revenue <- tw_collect(corrected)
  stopifnot(
    sum(revenue$revenue) == 175,
    sum(tw_collect(approved)$revenue) == 150
  )

  # Consumers can use ordinary R data. Keep the release identity with the export.
  saveRDS(revenue, file.path(path, "approved-revenue.rds"))
  saveRDS(corrected$outputs, file.path(path, "approved-revenue-reference.rds"))
  exported <- NULL
  if (requireNamespace("arrow", quietly = TRUE)) {
    exported <- tw_product("revenue_export", corrected) |>
      tw_set_target(tw_target_parquet(file.path(
        path,
        "approved-revenue.parquet"
      ))) |>
      tw_run()
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
