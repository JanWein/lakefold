test_that("batch measurements separate stock dates and aggregate flows explicitly", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dates <- as.Date(c("2026-08-31", "2026-09-30"))
  f$write(rbind(
    f$good,
    transform(f$good, date = dates[2], reserve = reserve * 2)
  ))
  published <- dr_run(f$pipeline, f$lake)
  stock <- reserve_metric()
  flow <- dr_metric(
    "risk.flow",
    "risk.validated",
    expr = sum(reserve),
    dimensions = "company",
    time_column = "date",
    time_behavior = "flow",
    unit = "EUR",
    approved = TRUE,
    code_version = "v1"
  )
  set <- dr_measure(
    f$lake,
    metrics = list(reserve = stock, cash = flow),
    by = "company",
    at = dates
  )
  values <- dr_collect(set)
  expect_s3_class(set, "dr_measurement_set")
  expect_output(
    dataraft.metrics:::print.dr_measurement_set(set),
    "Grouped by: company"
  )
  expect_identical(class(values), c("tbl_df", "tbl", "data.frame"))
  expect_named(values, c("company", ".metric", ".period", ".unit", "value"))
  expect_equal(values$value, c(100, 200, 200, 400, 100, 200, 200, 400))
  expect_identical(values$.period[[3]], dates[2])
  dr_report_release(f$lake, "grouped", set, "v1")
  expect_equal(dr_report_read(f$lake, "grouped", values_only = TRUE), values)
  expect_equal(
    vapply(set, function(x) attr(x, "dr_manifest")$release_id, character(1)),
    rep(published$release_id, 4),
    ignore_attr = TRUE
  )
  aggregate <- dr_measure(
    f$lake,
    metrics = list(flow),
    at = dates,
    period = "aggregate"
  )
  expect_equal(dr_collect(aggregate)$value, 900)
  expect_identical(dr_collect(aggregate)$.period[[1]], dates)
  expect_equal(dr_measure(f$lake, flow, at = dates)$value, 900)
  expect_snapshot(
    error = TRUE,
    dr_measure(f$lake, metrics = list(stock), at = dates, period = "aggregate")
  )
})

test_that("measurement sets retain pinned inputs and report evidence", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  published <- dr_run(f$pipeline, f$lake)
  # A product publication supplies the exact immutable result reference.
  original <- dr_product(
    "risk.product",
    contract = f$contract,
    code_version = "v1"
  ) |>
    dr_add_source(dr_source_release(f$lake, "risk.validated")) |>
    dr_publish(to = f$lake)
  metric <- reserve_metric("risk.product")
  before <- dr_measure(original, metrics = list(reserve = metric))
  f$write(transform(f$good, reserve = reserve * 2))
  dr_run(f$pipeline, f$lake)
  corrected <- dr_product(
    "risk.product",
    contract = f$contract,
    code_version = "v1"
  ) |>
    dr_add_source(dr_source_release(f$lake, "risk.validated")) |>
    dr_publish(to = f$lake)
  expect_equal(
    dr_collect(dr_measure(original, metrics = list(metric)))$value,
    300
  )
  expect_equal(
    dr_collect(dr_measure(corrected, metrics = list(metric)))$value,
    600
  )
  saved <- dr_report_release(f$lake, "monthly", before, "v1")
  retry <- dr_report_release(
    f$lake,
    "monthly",
    dr_measure(original, metrics = list(reserve = metric)),
    "v1"
  )
  expect_identical(retry, saved)
  expect_equal(
    dr_report_read(f$lake, "monthly", values_only = TRUE),
    dr_collect(before)
  )
  expect_snapshot(
    error = TRUE,
    dr_report_release(
      f$lake,
      "monthly",
      dr_measure(original, metrics = list(renamed = metric)),
      "v1"
    )
  )
  expect_identical(DBI::dbIsValid(f$lake$con), TRUE)
  changed <- before
  changed[[1]]$value <- 123
  expect_snapshot(error = TRUE, dr_report_release(f$lake, "bad", changed, "v1"))
  expect_identical(DBI::dbIsValid(f$lake$con), TRUE)
  changed <- before
  attr(changed[[1]], "dr_manifest")$release_id <- corrected$release_id
  expect_snapshot(error = TRUE, dr_collect(changed))
  changed <- before
  attr(changed, "dr_set_metadata")[[1]]$unit <- "USD"
  expect_snapshot(error = TRUE, dr_report_release(f$lake, "bad", changed, "v1"))
})

test_that("managed report connections close on success and failure", {
  root <- withr::local_tempdir()
  lake <- dr_open_lake(root)
  on.exit(if (DBI::dbIsValid(lake$con)) dr_close_lake(lake), add = TRUE)
  dr_write_data(lake, data.frame(id = 1:2, amount = c(10, 20)), "orders")
  total <- dr_metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "v1"
  )
  measured <- dr_measure(lake, metrics = list(total))
  config <- lake$config
  dr_close_lake(lake)
  saved <- dr_report_release(config, "one", measured, "v1")
  expect_equal(dr_report_read(root, "one", values_only = TRUE)$value, 30)
  expect_equal(dr_report_release(root, "one", measured, "v1"), saved)
  expect_snapshot(
    error = TRUE,
    dr_report_release(config, "one", measured, "v2")
  )
  expect_snapshot(error = TRUE, dr_report_read(config, "missing"))
  # Reopening in the other access mode fails if a managed connection leaked.
  lake <- dr_open_lake(root)
  expect_equal(dr_report_read(lake, "one")$id, "one")
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
  expect_equal(nrow(dr_registry(lake, "reports")), 1)
})

test_that("batch measurement rejects ambiguous labels and grouping columns", {
  metric <- reserve_metric()
  expect_snapshot(
    error = TRUE,
    dr_measure(NULL, metrics = list(x = metric, x = metric))
  )
  expect_snapshot(
    error = TRUE,
    dr_measure(NULL, metric, metrics = list(metric))
  )
  expect_snapshot(
    error = TRUE,
    dr_measure(NULL, metrics = list(metric), by = ".metric")
  )
  expect_snapshot(
    error = TRUE,
    dr_measure(NULL, metrics = list(metric), at = c(1, 1))
  )
})

test_that("batch calculation manages one owned connection and preserves closed result pins", {
  root <- withr::local_tempdir()
  dates <- as.Date(c("2026-08-31", "2026-09-30"))
  original <- dr_product(
    "balances",
    data.frame(date = dates, amount = c(10, 20))
  ) |>
    dr_publish(to = root)
  stock <- dr_metric(
    "balances.total",
    "balances",
    expr = sum(amount),
    time_column = "date",
    approved = TRUE,
    code_version = "v1"
  )
  actual_connect <- dataraft.lake::dr_connect_lake
  opened <- list()
  local_family_bindings(
    dr_connect_lake = function(...) {
      lake <- actual_connect(...)
      opened[[length(opened) + 1L]] <<- lake
      lake
    },
    .package = "dataraft"
  )
  measured <- dr_measure(original, metrics = list(stock), at = dates)
  expect_equal(dr_collect(measured)$value, c(10, 20))
  expect_length(opened, 1L)
  expect_identical(DBI::dbIsValid(opened[[1]]$con), FALSE)
  expect_snapshot(
    error = TRUE,
    dr_measure(
      original,
      metrics = list(stock),
      at = dates,
      period = "aggregate"
    )
  )
  expect_length(opened, 2L)
  expect_identical(DBI::dbIsValid(opened[[2]]$con), FALSE)
  lake <- dr_open_lake(root)
  on.exit(dr_close_lake(lake), add = TRUE)
  expect_equal(dr_measure(lake, stock, at = dates[1])$value, 10)
  expect_snapshot(error = TRUE, dr_collect(measured, unused = TRUE))
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
})
