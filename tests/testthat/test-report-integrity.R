test_that("reports preserve doubles and detect small numeric changes", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  definition <- dr_metric(
    "precision",
    "risk.validated",
    approved = TRUE,
    code_version = "v1",
    compute = function(data, dimensions, params) {
      data.frame(value = params$value)
    }
  )
  numbers <- c(
    9007199254740991,
    .Machine$double.xmax,
    .Machine$double.xmin,
    1.2345678901234567
  )
  for (i in seq_along(numbers)) {
    value <- dr_measure(f$lake, definition, params = list(value = numbers[i]))
    dr_report_release(f$lake, paste0("report", i), list(total = value), "v1")
    actual <- dr_report_read(f$lake, paste0("report", i), values_only = TRUE)
    expect_identical(as.double(actual$total$value), numbers[i])
  }
  changed <- dr_measure(f$lake, definition, params = list(value = numbers[1]))
  changed$value <- changed$value - 1
  expect_snapshot(
    error = TRUE,
    dr_report_release(f$lake, "changed", list(total = changed), "v1")
  )
})

test_that("nested report values are rejected before any report is written", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  definition <- dr_metric(
    "nested",
    "risk.validated",
    approved = TRUE,
    code_version = "v1",
    compute = function(data, dimensions, params) {
      tibble::tibble(value = list(c(low = 100, high = 200)))
    }
  )
  value <- dr_measure(f$lake, definition)
  expect_snapshot(
    error = TRUE,
    dr_report_release(f$lake, "nested", list(total = value), "v1")
  )
  expect_equal(nrow(dr_registry(f$lake, "reports")), 0L)
})
