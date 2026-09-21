test_that("published results pin measures after later releases", {
  skip_if_not_installed("duckdb")
  config <- tw_lake_config(path = file.path(withr::local_tempdir(), "lake"))
  first <- tw_ingest(data.frame(amount = 10), to = config, name = "orders")
  later <- tw_ingest(data.frame(amount = 40), to = config, name = "orders")
  total <- tw_metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  result <- first |> tw_measure(total)
  expect_equal(result$value, 10)
  expect_identical(attr(result, "tw_manifest")$release_id, first$release_id)
  expect_identical(attr(result, "tw_manifest")$code_version, "metric-v1")
  expect_equal(tw_measure(later, total)$value, 40)
  lake <- tw_connect_lake(config)
  withr::defer(tw_close_lake(lake))
  expect_false(any(tw_registry(lake, "assets")$kind == "metric"))
  expect_error(tw_measure(first, total, release = later$release_id), "pinned")
  expect_error(
    tw_measure(first, total, record = TRUE),
    "connected writable lake"
  )
})

test_that("result measurements borrow live lakes and recover closed handles", {
  skip_if_not_installed("duckdb")
  lake <- tw_open_lake(withr::local_tempdir())
  accepted <- tw_ingest(data.frame(amount = 12), to = lake, name = "orders")
  total <- tw_metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  expect_equal(tw_measure(accepted, total)$value, 12)
  expect_true(DBI::dbIsValid(lake$con))
  tw_close_lake(lake)
  opened <- NULL
  connect <- tw_connect_lake
  testthat::local_mocked_bindings(tw_connect_lake = function(
    config,
    read_only = FALSE
  ) {
    expect_true(read_only)
    opened <<- connect(config, read_only = read_only)
    opened
  })
  expect_equal(tw_measure(accepted, total)$value, 12)
  expect_false(DBI::dbIsValid(opened$con))
  expect_false(DBI::dbIsValid(lake$con))
})

test_that("measure result preflight rejects failed runs, wrong assets and approvals", {
  total <- tw_metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  result <- structure(
    list(status = "blocked", asset = "orders", release_id = "r1"),
    class = "tw_run_result"
  )
  testthat::local_mocked_bindings(tw_connect_lake = function(...) {
    stop("must not connect")
  })
  expect_error(tw_measure(result, total), "successful published result")
  result$status <- "published"
  result$asset <- "another_asset"
  expect_error(tw_measure(result, total), "does not match")
  result$asset <- "orders"
  total$approved <- FALSE
  expect_error(tw_measure(result, total, record = TRUE), "Exploratory")
})

test_that("result measurements keep stock-date checks and close on errors", {
  skip_if_not_installed("duckdb")
  config <- tw_lake_config(path = file.path(withr::local_tempdir(), "lake"))
  data <- data.frame(
    date = as.Date(c("2026-01-31", "2026-02-28")),
    amount = c(10, 20)
  )
  accepted <- tw_ingest(data, to = config, name = "balances")
  stock <- tw_metric(
    "balances.total",
    "balances",
    expr = sum(amount),
    time_column = "date",
    approved = TRUE,
    code_version = "metric-v1"
  )
  opened <- NULL
  connect <- tw_connect_lake
  testthat::local_mocked_bindings(tw_connect_lake = function(
    config,
    read_only = FALSE
  ) {
    expect_true(read_only)
    opened <<- connect(config, read_only = read_only)
    opened
  })
  expect_error(tw_measure(accepted, stock), "exactly one")
  expect_false(DBI::dbIsValid(opened$con))
  expect_equal(
    tw_measure(accepted, stock, at = as.Date("2026-01-31"))$value,
    10
  )
  expect_false(DBI::dbIsValid(opened$con))
})
