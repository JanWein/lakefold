test_that("published results pin measures after later releases", {
  skip_if_not_installed("duckdb")
  config <- lake_config(path = file.path(withr::local_tempdir(), "lake"))
  first <- ingest(data.frame(amount = 10), to = config, name = "orders")
  later <- ingest(data.frame(amount = 40), to = config, name = "orders")
  total <- metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  result <- first |> measure(total)
  expect_equal(result$value, 10)
  expect_identical(attr(result, "tw_manifest")$release_id, first$release_id)
  expect_identical(attr(result, "tw_manifest")$code_version, "metric-v1")
  expect_equal(measure(later, total)$value, 40)
  lake <- connect_lake(config)
  withr::defer(close_lake(lake))
  expect_false(any(registry(lake, "assets")$kind == "metric"))
  expect_error(measure(first, total, release = later$release_id), "pinned")
  expect_error(measure(first, total, record = TRUE), "connected writable lake")
})

test_that("result measurements borrow live lakes and recover closed handles", {
  skip_if_not_installed("duckdb")
  lake <- open_lake(withr::local_tempdir())
  accepted <- ingest(data.frame(amount = 12), to = lake, name = "orders")
  total <- metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  expect_equal(measure(accepted, total)$value, 12)
  expect_true(DBI::dbIsValid(lake$con))
  close_lake(lake)
  opened <- NULL
  connect <- connect_lake
  testthat::local_mocked_bindings(connect_lake = function(
    config,
    read_only = FALSE
  ) {
    expect_true(read_only)
    opened <<- connect(config, read_only = read_only)
    opened
  })
  expect_equal(measure(accepted, total)$value, 12)
  expect_false(DBI::dbIsValid(opened$con))
  expect_false(DBI::dbIsValid(lake$con))
})

test_that("measure result preflight rejects failed runs, wrong assets and approvals", {
  total <- metric(
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
  testthat::local_mocked_bindings(connect_lake = function(...) {
    stop("must not connect")
  })
  expect_error(measure(result, total), "successful published result")
  result$status <- "published"
  result$asset <- "another_asset"
  expect_error(measure(result, total), "does not match")
  result$asset <- "orders"
  total$approved <- FALSE
  expect_error(measure(result, total, record = TRUE), "Exploratory")
})

test_that("result measurements keep stock-date checks and close on errors", {
  skip_if_not_installed("duckdb")
  config <- lake_config(path = file.path(withr::local_tempdir(), "lake"))
  data <- data.frame(
    date = as.Date(c("2026-01-31", "2026-02-28")),
    amount = c(10, 20)
  )
  accepted <- ingest(data, to = config, name = "balances")
  stock <- metric(
    "balances.total",
    "balances",
    expr = sum(amount),
    time_column = "date",
    approved = TRUE,
    code_version = "metric-v1"
  )
  opened <- NULL
  connect <- connect_lake
  testthat::local_mocked_bindings(connect_lake = function(
    config,
    read_only = FALSE
  ) {
    expect_true(read_only)
    opened <<- connect(config, read_only = read_only)
    opened
  })
  expect_error(measure(accepted, stock), "exactly one")
  expect_false(DBI::dbIsValid(opened$con))
  expect_equal(measure(accepted, stock, at = as.Date("2026-01-31"))$value, 10)
  expect_false(DBI::dbIsValid(opened$con))
})
