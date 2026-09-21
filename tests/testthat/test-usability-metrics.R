test_that("related definitions share metadata without evaluating expressions", {
  definitions <- dr_metric_set(
    "orders",
    total = sum(amount),
    count = dplyr::n(),
    dimensions = "company",
    time_column = "date",
    time_behavior = c(total = "flow", count = "stock"),
    units = c(total = "EUR")
  )
  expect_identical(class(definitions), "list")
  expect_named(definitions, c("total", "count"))
  expect_identical(definitions$total$id, "orders.total")
  expect_identical(definitions$count$unit, "")
  expect_identical(definitions$total$time_behavior, "flow")
  expect_identical(definitions$count$time_behavior, "stock")
  expect_null(definitions$total$code_version)
  expect_snapshot(
    error = TRUE,
    dr_metric("m", "orders", expr = sum(amount), approved = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    dr_metric_set(
      "orders",
      total = sum(amount),
      time_behavior = c(other = "stock")
    )
  )
})

test_that("exploration computes without registration and cannot become a report", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  definitions <- dr_metric_set("risk.validated", reserve = sum(reserve))
  values <- dr_measure(f$lake, metrics = definitions)
  expect_equal(dr_collect(values)$value, 300)
  expect_equal(
    query(
      f$lake,
      paste(
        "SELECT count(*) AS n FROM",
        meta(f$lake, "assets"),
        "WHERE kind = 'metric'"
      )
    )$n,
    0
  )
  expect_snapshot(
    error = TRUE,
    dr_measure(f$lake, definitions$reserve, record = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    dr_report_release(values, "exploration", code_version = "v1")
  )
  single <- values[[1]]
  attr(single, "dr_manifest")$metric_definition$approved <- TRUE
  expect_snapshot(
    error = TRUE,
    dr_report_release(single, "mutated", code_version = "v1")
  )
  expect_equal(
    query(
      f$lake,
      paste("SELECT count(*) AS n FROM", meta(f$lake, "reports"))
    )$n,
    0
  )
})

test_that("data-first reports retain exact releases and borrow existing lakes", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  original <- dr_run(f$pipeline, f$lake)
  definitions <- dr_metric_set(
    "risk.validated",
    reserve = sum(reserve),
    code_version = "v1",
    approved = TRUE
  )
  values <- dr_measure(f$lake, metrics = definitions)
  report <- values |> dr_report_release("monthly", code_version = "v1")
  expect_identical(
    report$measures[[1]]$manifest$release_id,
    original$release_id
  )
  expect_identical(DBI::dbIsValid(f$lake$con), TRUE)
  expect_null(attr(report$measures[[1]]$values, "dr_quality_reference"))
  expect_identical(report, dr_report_release(f$lake, "monthly", values, "v1"))
  expect_equal(
    dr_report_read(f$lake, "monthly", values_only = TRUE),
    dr_collect(values)
  )
  single <- values[[1]]
  expect_no_error(
    single |> dr_report_release("single", to = f$lake, code_version = "v1")
  )
  attr(single, "dr_quality_reference")$release <- "different"
  expect_snapshot(
    error = TRUE,
    dr_report_release(single, "bad-ref", code_version = "v1")
  )
})

test_that("saved report destinations reopen after the original connection closes", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  published <- dr_run(f$pipeline, f$lake)
  values <- dr_measure(f$lake, reserve_metric(), release = published$release_id)
  dr_disconnect_lake(f$lake)
  saved <- values |> dr_report_release("reopened", code_version = "v1")
  expect_identical(
    saved$measures[[1]]$manifest$release_id,
    published$release_id
  )
  expect_equal(
    dr_report_read(f$lake$config, "reopened")$measures[[1]]$values$value,
    300
  )
})

test_that("decimal totals and database counts collect together without changing evidence", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  definitions <- dr_metric_set(
    "risk.validated",
    total = sum(reserve),
    count = dplyr::n(),
    approved = TRUE,
    code_version = "v1"
  )
  results <- dr_measure(f$lake, metrics = definitions)
  before <- lapply(results, attributes)
  expect_equal(dr_collect(results)$value, c(300, 2))
  expect_identical(lapply(results, attributes), before)
  results |> dr_report_release("total-and-count", code_version = "v1")
  expect_equal(
    dr_report_read(f$lake, "total-and-count", values_only = TRUE),
    dr_collect(results)
  )
})

test_that("mixed metric tables never round large integer counts", {
  skip_if_not_installed("bit64")
  make_result <- function(value) {
    x <- tibble::tibble(value = value)
    attr(x, "dr_manifest") <- list(by = character())
    x
  }
  metadata <- list(
    list(metric = "amount", period = NULL, unit = "EUR"),
    list(metric = "count", period = NULL, unit = "")
  )
  exact <- bit64::as.integer64(c("9007199254740992", "-9007199254740992"))
  values <- list(make_result(1.25), make_result(exact))
  expect_equal(
    measurement_set_table(values, metadata)$value,
    c(1.25, 2^53, -2^53)
  )
  expect_identical(values[[2]]$value, exact)
  values[[2]] <- make_result(bit64::as.integer64("9007199254740993"))
  expect_snapshot(error = TRUE, measurement_set_table(values, metadata))
  expect_identical(as.character(values[[2]]$value), "9007199254740993")
})

test_that("report storage refuses integers it cannot read back exactly before IO", {
  skip_if_not_installed("bit64")
  definition <- dr_metric(
    "large.count",
    "orders",
    expr = dplyr::n(),
    approved = TRUE,
    code_version = "v1"
  )
  value <- tibble::tibble(value = bit64::as.integer64("9007199254740993"))
  attr(value, "dr_manifest") <- list(
    metric = definition$id,
    metric_version = definition$version,
    metric_definition = canonical(definition),
    metric_hash = fingerprint(definition),
    product = definition$product,
    code_version = definition$code_version,
    result_hash = fingerprint(value)
  )
  local_family_bindings(report_connection = function(...) {
    stop("must not connect")
  })
  expect_snapshot(
    error = TRUE,
    dr_report_release(value, "huge-count", to = "unused", code_version = "v1")
  )
  expect_identical(as.character(value$value), "9007199254740993")
})
