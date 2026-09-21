layered_catalog_state <- function(config) {
  lake <- dr_connect_lake(config)
  on.exit(dr_close_lake(lake))
  tables <- DBI::dbGetQuery(
    lake$con,
    paste(
      "SELECT table_schema, table_name FROM information_schema.tables",
      "WHERE table_catalog = 'lake'",
      "AND table_schema IN ('raw', 'staging', 'core', 'marts')",
      "ORDER BY table_schema, table_name"
    )
  )
  list(
    tables = tables,
    raw_tables = tables$table_name[tables$table_schema == "raw"],
    raw_releases = dr_releases(lake, "orders")$release_id,
    consumer_releases = dr_releases(lake, "customer_revenue")$release_id,
    consumer = dr_read_release(lake, "customer_revenue") |>
      dplyr::arrange(customer_id),
    mutable_mart = DBI::dbGetQuery(
      lake$con,
      paste(
        'SELECT customer_id, revenue FROM "lake"."marts"."customer_revenue"',
        "ORDER BY customer_id"
      )
    )
  )
}

layered_expect_build <- function(result, accepted) {
  expect_true(
    result$success,
    info = paste(result$stdout, result$stderr, result$artifact_error)
  )
  if (!isTRUE(result$success)) {
    return(FALSE)
  }
  source <- result$manifest$sources[["source.layered_workflow.raw.orders"]]
  expect_identical(source$database, "lake")
  expect_identical(source$schema, "raw")
  expect_identical(source$identifier, accepted$outputs$table)
  metadata <- source$config$meta$dataraft
  if (is.null(metadata)) {
    metadata <- source$meta$dataraft
  }
  expect_identical(metadata$release_id, accepted$release_id)
  expect_identical(metadata$run_id, accepted$run_id)
  expect_identical(metadata$asset, "orders")
  nodes <- result$manifest$nodes
  expect_true(
    "source.layered_workflow.raw.orders" %in%
      nodes[["model.layered_workflow.stg_orders"]]$depends_on$nodes
  )
  expect_true(
    "model.layered_workflow.stg_orders" %in%
      nodes[["model.layered_workflow.core_orders"]]$depends_on$nodes
  )
  expect_true(
    "model.layered_workflow.core_orders" %in%
      nodes[["model.layered_workflow.customer_revenue"]]$depends_on$nodes
  )
  expect_true(isTRUE(
    nodes[["model.layered_workflow.customer_revenue"]]$config$contract$enforced
  ))
  TRUE
}

test_that("CSV, Excel and API deliveries retain approved outputs across layered failures", {
  executable <- Sys.getenv("DATARAFT_DBT_EXECUTABLE")
  skip_if(
    !nzchar(executable),
    "Set DATARAFT_DBT_EXECUTABLE for the real layered dbt integration test"
  )
  for (package in c(
    "duckdb",
    "yaml",
    "readxl",
    "pointblank",
    "httr2",
    "webfakes"
  )) {
    skip_if_not_installed(package)
  }
  backend <- Sys.getenv("DATARAFT_TEST_BACKEND", "duckdb")
  directory <- withr::local_tempdir()
  config <- dr_lake_config(
    dr_registry_duckdb(file.path(directory, "catalog.duckdb")),
    dr_storage_local(file.path(directory, "data")),
    landing = file.path(directory, "landing"),
    backend = backend,
    layers = c("raw", "staging", "core", "marts")
  )
  first_data <- data.frame(
    order_id = 1:3,
    customer_id = c(101L, 101L, 102L),
    amount = c(10.25, 20.5, 30.25)
  )
  csv <- file.path(directory, "orders.csv")
  utils::write.csv(first_data, csv, row.names = FALSE)
  first_raw <- dr_ingest(
    csv,
    config,
    "orders",
    quality = list(nonnegative = ~ amount >= 0),
    business_date = as.Date("2026-09-01")
  )
  expect_identical(first_raw$status, "published")
  expect_null(first_raw$output_lake)
  expect_equal(dr_collect(first_raw), tibble::as_tibble(first_data))
  expect_identical(first_raw$outputs$schema, "raw")
  expect_equal(first_raw$inputs$business_date, "2026-09-01")
  expect_true(all(nzchar(first_raw$inputs$received_at)))
  expect_equal(
    digest::digest(file = first_raw$inputs$landed_path[[1]], algo = "sha256"),
    digest::digest(file = csv, algo = "sha256")
  )
  expect_setequal(dr_quality(first_raw)$stage, c("ingest", "candidate"))

  project <- dr_dbt_init(
    file.path(directory, "dbt"),
    config,
    name = "layered_workflow",
    sources = list(orders = first_raw),
    executable = executable
  )
  expect_false(dir.exists(file.path(project$path, "seeds")))
  schema_file <- file.path(project$path, "models", "schema.yml")
  properties <- yaml::read_yaml(schema_file)
  # Preserve YAML sequences when editing an existing model properties file.
  properties$models <- lapply(properties$models, function(model) {
    model$columns <- lapply(model$columns, function(column) {
      for (field in c("tests", "data_tests")) {
        if (!is.null(column[[field]])) {
          column[[field]] <- as.list(column[[field]])
        }
      }
      column
    })
    model
  })
  model_names <- vapply(properties$models, `[[`, character(1), "name")
  mart_contract <- dr_contract(
    columns = c(customer_id = "integer", revenue = "numeric"),
    key = "customer_id"
  )
  properties$models[[which(model_names == "customer_revenue")]] <-
    dr_dbt_contract(mart_contract, "customer_revenue")$models[[1L]]
  yaml::write_yaml(properties, schema_file)
  dir.create(file.path(project$path, "tests"))
  writeLines(
    c(
      "select customer_id from {{ ref('customer_revenue') }}",
      "where revenue > 1000"
    ),
    file.path(project$path, "tests", "revenue_within_limit.sql")
  )

  first_build <- dr_dbt_build(project, echo = FALSE, stop_on_failure = FALSE)
  if (!layered_expect_build(first_build, first_raw)) {
    return(invisible(NULL))
  }
  first <- dr_dbt_publish(config, first_build, "customer_revenue")
  expect_identical(first$status, "published")
  expect_null(first$output_lake)
  expect_identical(first$outputs$schema, "marts")
  expect_identical(
    first$inputs$invocation_id,
    first_build$manifest$metadata$invocation_id
  )
  first_values <- dr_collect(first) |> dplyr::arrange(customer_id)
  expect_equal(first_values$revenue, c(30.75, 30.25))
  state <- layered_catalog_state(config)
  expect_setequal(
    state$tables$table_schema,
    c("raw", "staging", "core", "marts")
  )
  expect_true(all(
    c(
      first_raw$outputs$table,
      "stg_orders",
      "core_orders",
      "customer_revenue",
      first$outputs$table
    ) %in%
      state$tables$table_name
  ))

  workbook <- test_path("..", "fixtures", "layered-orders.xlsx")
  prepared_excel <- function(path) {
    readxl::read_excel(path) |>
      dplyr::mutate(
        order_id = as.integer(order_id),
        customer_id = as.integer(customer_id)
      )
  }
  second_raw <- dr_ingest(
    workbook,
    config,
    "orders",
    reader = prepared_excel,
    quality = list(nonnegative = ~ amount >= 0),
    business_date = as.Date("2026-09-02")
  )
  expect_identical(second_raw$status, "published")
  expect_equal(dr_collect(second_raw)$amount, c(100.25, 200.5, 300.25))
  expect_equal(
    digest::digest(file = second_raw$inputs$landed_path[[1]], algo = "sha256"),
    digest::digest(file = workbook, algo = "sha256")
  )
  dr_dbt_sources(project, list(orders = second_raw), name = "raw")
  second_build <- dr_dbt_build(project, echo = FALSE, stop_on_failure = FALSE)
  if (!layered_expect_build(second_build, second_raw)) {
    return(invisible(NULL))
  }
  second <- dr_dbt_publish(config, second_build, "customer_revenue")
  expect_identical(second$status, "published")
  expect_false(identical(first$release_id, second$release_id))
  second_values <- dr_collect(second) |> dplyr::arrange(customer_id)
  expect_equal(second_values$revenue, c(300.75, 300.25))
  expect_equal(dr_collect(first) |> dplyr::arrange(customer_id), first_values)
  expect_equal(dr_collect(first_raw), tibble::as_tibble(first_data))

  binding_file <- file.path(project$path, "models", "dataraft_sources_raw.yml")
  binding_before <- readLines(binding_file)
  before_rejection <- layered_catalog_state(config)
  invalid <- first_data
  invalid$amount[[1]] <- -1
  invalid_csv <- file.path(directory, "invalid-orders.csv")
  utils::write.csv(invalid, invalid_csv, row.names = FALSE)
  native_rejected <- dr_ingest(
    invalid_csv,
    config,
    "orders",
    quality = list(nonnegative = ~ amount >= 0),
    stop_on_failure = FALSE
  )
  pointblank_rejected <- dr_ingest(
    invalid,
    config,
    "orders",
    quality = dr_pointblank_checks("nonnegative", function(data) {
      pointblank::create_agent(data) |>
        pointblank::col_vals_gte("amount", 0)
    }),
    stop_on_failure = FALSE
  )
  for (rejected in list(native_rejected, pointblank_rejected)) {
    expect_identical(
      rejected$status,
      "blocked",
      info = if (inherits(rejected$error, "condition")) {
        conditionMessage(rejected$error)
      }
    )
    if (!identical(rejected$status, "blocked")) {
      return(invisible(NULL))
    }
    expect_null(rejected$outputs)
    expect_true(all(file.exists(rejected$inputs$landed_path)))
    expect_identical(unique(dr_quality(rejected)$stage), "ingest")
    expect_error(
      dr_dbt_sources(project, list(orders = rejected), name = "raw"),
      "successful"
    )
    expect_equal(readLines(binding_file), binding_before)
  }
  expect_true(any(
    dr_quality(native_rejected)$engine == "r" &
      dr_quality(native_rejected)$status == "failed"
  ))
  expect_true(any(
    dr_quality(pointblank_rejected)$engine == "pointblank" &
      dr_quality(pointblank_rejected)$status == "failed"
  ))
  expect_equal(
    digest::digest(
      file = native_rejected$inputs$landed_path[[1]],
      algo = "sha256"
    ),
    digest::digest(file = invalid_csv, algo = "sha256")
  )
  after_rejection <- layered_catalog_state(config)
  expect_equal(after_rejection$raw_tables, before_rejection$raw_tables)
  expect_equal(after_rejection$raw_releases, before_rejection$raw_releases)
  expect_equal(
    after_rejection$consumer_releases,
    before_rejection$consumer_releases
  )
  expect_equal(after_rejection$consumer, second_values)

  app <- webfakes::new_app()
  app$get("/orders", function(req, res) {
    res$send_json(data.frame(
      order_id = 1:3,
      customer_id = c(101L, 101L, 102L),
      amount = c(1000.25, 2000.5, 3000.25)
    ))
  })
  server <- webfakes::new_app_process(app)
  withr::defer(server$stop())
  request <- httr2::request(paste0(sub("/$", "", server$url()), "/orders"))
  api_raw <- dr_ingest(
    dr_source_api(request),
    config,
    "orders",
    quality = list(nonnegative = ~ amount >= 0),
    business_date = as.Date("2026-09-03")
  )
  expect_identical(api_raw$status, "published")
  expect_equal(dr_collect(api_raw)$amount, c(1000.25, 2000.5, 3000.25))
  expect_equal(
    readRDS(api_raw$inputs$landed_path[[1]])$amount,
    dr_collect(api_raw)$amount
  )
  dr_dbt_sources(project, list(orders = api_raw), name = "raw")
  failed <- dr_dbt_build(project, echo = FALSE, stop_on_failure = FALSE)
  expect_false(failed$success)
  expect_true(any(failed$results$status == "fail"))
  expect_identical(
    failed$results$status[
      failed$results$unique_id == "model.layered_workflow.customer_revenue"
    ],
    "success"
  )
  expect_identical(
    failed$manifest$sources[["source.layered_workflow.raw.orders"]]$identifier,
    api_raw$outputs$table
  )
  expect_error(
    dr_dbt_publish(config, failed, "customer_revenue"),
    "successful dbt build"
  )
  after_failure <- layered_catalog_state(config)
  expect_equal(
    after_failure$consumer_releases,
    before_rejection$consumer_releases
  )
  expect_equal(after_failure$consumer, second_values)
  expect_equal(after_failure$mutable_mart$revenue, c(3000.75, 3000.25))
  expect_equal(dr_collect(first) |> dplyr::arrange(customer_id), first_values)
  expect_equal(dr_collect(second) |> dplyr::arrange(customer_id), second_values)
})
