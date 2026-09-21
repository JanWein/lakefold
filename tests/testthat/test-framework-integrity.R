test_that("identifiers neither consume nor create the R random seed", {
  withr::local_seed(42)
  seed <- .Random.seed
  ids <- replicate(100, uid())
  expect_identical(.Random.seed, seed)
  expect_length(unique(ids), 100)
  rm(".Random.seed", envir = .GlobalEnv)
  uid()
  expect_false(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
})

test_that("full formulas distinguish metric definitions", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  expression <- rlang::parse_expr(paste0(
    "sum(reserve + ",
    paste(rep("0", 50), collapse = " + "),
    ") + 1"
  ))
  first <- dr_metric(
    "long.total",
    "risk.validated",
    expr = !!expression,
    approved = TRUE,
    code_version = "v1"
  )
  changed <- first
  changed$expr <- rlang::new_quosure(
    rlang::parse_expr(sub("1$", "2", rlang::expr_deparse(expression))),
    globalenv()
  )
  expect_false(identical(fingerprint(first), fingerprint(changed)))
  expect_match(canonical(first)$expr$expression, "\\+ 1$")
  expect_equal(dr_measure(f$lake, first)$value, 301)
  expect_error(dr_measure(f$lake, changed), "version bump")
  changed$version <- "2.0.0"
  expect_equal(dr_measure(f$lake, changed)$value, 302)
  registered <- dr_registry(f$lake, "assets")
  expect_true(any(grepl(
    "expression",
    registered$definition[registered$id == first$id]
  )))
})

test_that("all supported data pronouns enforce the missing-value policy", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_write_data(f$lake, data.frame(amount = c(10, NA)), "nullable")
  expressions <- list(
    rlang::expr(sum(amount, na.rm = TRUE)),
    rlang::expr(sum(.data$amount, na.rm = TRUE)),
    rlang::expr(sum(.data[["amount"]], na.rm = TRUE))
  )
  for (i in seq_along(expressions)) {
    metric <- dr_metric(
      paste0("total", i),
      "nullable",
      expr = !!expressions[[i]],
      approved = TRUE,
      code_version = "v1"
    )
    expect_error(dr_measure(f$lake, metric), "Missing metric input: amount")
  }
  column <- "amount"
  metric <- dr_metric(
    "dynamic",
    "nullable",
    sum(.data[[column]], na.rm = TRUE),
    approved = TRUE,
    code_version = "v1"
  )
  expect_error(
    dr_measure(f$lake, metric, record = FALSE),
    "Missing metric input"
  )
  metric$expr <- rlang::new_quosure(
    quote(sum(.data[[column]], na.rm = TRUE)),
    environment()
  )
  expect_error(dr_measure(f$lake, metric, record = FALSE), "input_columns")
  metric$input_columns <- "amount"
  expect_error(
    dr_measure(f$lake, metric, record = FALSE),
    "Missing metric input"
  )
  metric$na_policy <- "expression"
  expect_equal(dr_measure(f$lake, metric, record = FALSE)$value, 10)
  expect_equal(
    dr_measure(
      f$lake,
      dr_metric(
        "count",
        "nullable",
        dplyr::n(),
        approved = TRUE,
        code_version = "v1"
      )
    )$value,
    2
  )
})

test_that("custom metric input declarations are optional and validated", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_write_data(
    f$lake,
    data.frame(amount = 10, optional = NA_character_),
    "nullable"
  )
  metric <- dr_metric(
    "custom",
    "nullable",
    compute = function(data, dimensions, params) {
      dplyr::summarise(data, value = sum(amount, na.rm = TRUE))
    },
    approved = TRUE,
    code_version = "v1"
  )
  expect_error(dr_measure(f$lake, metric, record = FALSE), "optional")
  metric$input_columns <- "amount"
  expect_equal(dr_measure(f$lake, metric, record = FALSE)$value, 10)
  metric$input_columns <- "absent"
  expect_error(
    dr_measure(f$lake, metric, record = FALSE),
    "columns are missing"
  )
})

test_that("read-only attachments protect data and metadata while supporting analyses", {
  root <- tempfile("dataraft-read-only-")
  lake <- dr_open_lake(
    root,
    backend = Sys.getenv("DATARAFT_TEST_BACKEND", "duckdb")
  )
  on.exit({
    dr_close_lake(lake)
    unlink(root, recursive = TRUE)
  })
  dr_write_data(lake, data.frame(id = 1L, amount = 10), "orders")
  metric <- dr_metric(
    "total",
    "orders",
    sum(amount, na.rm = TRUE),
    approved = TRUE,
    code_version = "v1"
  )
  measured <- dr_measure(lake, metric)
  dr_report_release(lake, "report", list(total = measured), "v1")
  tables <- c(
    "assets",
    "runs",
    "reports",
    "lineage_edges",
    "events",
    "schema_version"
  )
  before <- lapply(tables, function(x) dr_registry(lake, x))
  dr_close_lake(lake)
  lake <- dr_open_lake(root, read_only = TRUE)
  expect_equal(dr_measure(lake, metric)$value, 10)
  expect_equal(
    dr_report_read(lake, "report", values_only = TRUE)$total$value,
    10
  )
  expect_error(dr_measure(lake, metric, record = TRUE), class = "dr_read_only")
  expect_error(
    dr_write_data(lake, data.frame(id = 2L), "other"),
    class = "dr_read_only"
  )
  expect_error(dr_register(lake, metric), class = "dr_read_only")
  expect_error(
    dr_report_release(lake, "another", list(total = measured), "v1"),
    class = "dr_read_only"
  )
  expect_error(DBI::dbExecute(
    lake$con,
    paste("DELETE FROM", meta(lake, "reports"))
  ))
  expect_identical(lapply(tables, function(x) dr_registry(lake, x)), before)
  transient <- metric
  transient$id <- "transient"
  expect_equal(dr_measure(lake, transient)$value, 10)
  expect_equal(nrow(dr_registry(lake, "assets")), nrow(before[[1]]))
})

test_that("read-only opening never creates a missing lake", {
  root <- tempfile("dataraft-absent-")
  expect_error(dr_open_lake(root, read_only = TRUE), "must already exist")
  expect_false(dir.exists(root))
})

test_that("report retries ignore only volatile calculation times", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  metric <- reserve_metric()
  metric$dimensions <- c("company", "date")
  first <- dr_measure(f$lake, metric, by = "date")
  initial <- dr_report_release(f$lake, "monthly", list(total = first), "v1")
  saved <- dr_registry(f$lake, "reports")
  second <- dr_measure(f$lake, metric, by = "date")
  expect_no_error(
    retry <- dr_report_release(
      f$lake,
      "monthly",
      list(total = second),
      "v1"
    )
  )
  expect_identical(initial, retry)
  expect_s3_class(retry$measures$total$values$date, "Date")
  expect_identical(dr_registry(f$lake, "reports"), saved)
  expect_equal(dr_report_read(f$lake, "monthly", TRUE)$total$value, 300)
  expect_identical(
    dr_report_read(f$lake, "monthly")$measures$total$manifest$calculated_at,
    attr(first, "dr_manifest")$calculated_at
  )
  expect_error(
    dr_report_release(f$lake, "monthly", list(total = second), "v2"),
    "different content"
  )
  expect_error(
    dr_report_release(
      f$lake,
      "monthly",
      list(total = second),
      "v1",
      params = list(period = "changed")
    ),
    "different content"
  )
  changed <- f$good
  changed$reserve <- changed$reserve + 1
  f$write(changed)
  dr_run(f$pipeline, f$lake)
  expect_error(
    dr_report_release(
      f$lake,
      "monthly",
      list(total = dr_measure(f$lake, metric)),
      "v1"
    ),
    "different content"
  )
})

test_that("custom metric groups are unique and repeated lineage is deduplicated", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  metric <- reserve_metric()
  dr_measure(f$lake, metric)
  before <- dr_registry(f$lake, "lineage_edges")
  dr_measure(f$lake, metric)
  expect_identical(dr_registry(f$lake, "lineage_edges"), before)
  metric$compute <- function(data, dimensions, params) {
    data.frame(company = c("a", "a"), value = c(1, 2))
  }
  metric$expr <- NULL
  metric$version <- "2.0.0"
  expect_error(
    dr_measure(f$lake, metric, by = "company"),
    "one row per requested group"
  )
})


test_that("group order cannot change the identity of identical metric results", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  reverse <- FALSE
  metric <- dr_metric(
    "ordered",
    "risk.validated",
    dimensions = "company",
    compute = function(data, dimensions, params) {
      result <- data.frame(company = c("b", "a"), value = c(2, 1))
      if (reverse) result[2:1, ] else result
    },
    approved = TRUE,
    code_version = "v1"
  )
  first <- dr_measure(f$lake, metric, by = "company")
  reverse <- TRUE
  second <- dr_measure(f$lake, metric, by = "company")
  expect_equal(first$company, c("a", "b"))
  expect_identical(
    attr(first, "dr_manifest")$result_hash,
    attr(second, "dr_manifest")$result_hash
  )
  dr_report_release(f$lake, "ordered-report", list(total = first), "v1")
  expect_no_error(dr_report_release(
    f$lake,
    "ordered-report",
    list(total = second),
    "v1"
  ))
})
