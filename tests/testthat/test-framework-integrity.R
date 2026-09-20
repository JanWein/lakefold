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

test_that("full formulas distinguish previously abbreviated metric definitions", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  expression <- rlang::parse_expr(paste0(
    "sum(reserve + ",
    paste(rep("0", 50), collapse = " + "),
    ") + 1"
  ))
  first <- metric(
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
  expect_equal(measure(f$lake, first)$value, 301)
  expect_error(measure(f$lake, changed), "version bump")
  changed$version <- "2.0.0"
  expect_equal(measure(f$lake, changed)$value, 302)
  registered <- registry(f$lake, "assets")
  expect_true(any(grepl(
    "expression",
    registered$definition[registered$id == first$id]
  )))
})

test_that("legacy metric identities are preserved and require a new version", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  metric <- reserve_metric()
  legacy <- canonical(metric)
  legacy$expr <- "sum(...)"
  legacy$input_columns <- NULL
  insert_meta(
    f$lake,
    "assets",
    list(
      id = metric$id,
      version = metric$version,
      kind = "metric",
      owner = "Risk",
      description = "Legacy",
      definition = jencode(legacy),
      fingerprint = fingerprint(legacy),
      registered_at = now()
    )
  )
  old <- registry(f$lake, "assets")
  expect_error(register(f$lake, metric), class = "tw_legacy_metric")
  expect_identical(registry(f$lake, "assets"), old)
  metric$version <- "2.0.0"
  expect_no_error(register(f$lake, metric))
})

test_that("all supported data pronouns enforce the missing-value policy", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  write_data(f$lake, data.frame(amount = c(10, NA)), "nullable")
  expressions <- list(
    rlang::expr(sum(amount, na.rm = TRUE)),
    rlang::expr(sum(.data$amount, na.rm = TRUE)),
    rlang::expr(sum(.data[["amount"]], na.rm = TRUE))
  )
  for (i in seq_along(expressions)) {
    metric <- metric(
      paste0("total", i),
      "nullable",
      expr = !!expressions[[i]],
      approved = TRUE,
      code_version = "v1"
    )
    expect_error(measure(f$lake, metric), "Missing metric input: amount")
  }
  column <- "amount"
  metric <- metric(
    "dynamic",
    "nullable",
    sum(.data[[column]], na.rm = TRUE),
    approved = TRUE,
    code_version = "v1"
  )
  expect_error(
    measure(f$lake, metric, record = FALSE),
    "Missing metric input"
  )
  metric$expr <- rlang::new_quosure(
    quote(sum(.data[[column]], na.rm = TRUE)),
    environment()
  )
  expect_error(measure(f$lake, metric, record = FALSE), "input_columns")
  metric$input_columns <- "amount"
  expect_error(
    measure(f$lake, metric, record = FALSE),
    "Missing metric input"
  )
  metric$na_policy <- "expression"
  expect_equal(measure(f$lake, metric, record = FALSE)$value, 10)
  expect_equal(
    measure(
      f$lake,
      metric(
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
  write_data(
    f$lake,
    data.frame(amount = 10, optional = NA_character_),
    "nullable"
  )
  metric <- metric(
    "custom",
    "nullable",
    compute = function(data, dimensions, params) {
      dplyr::summarise(data, value = sum(amount, na.rm = TRUE))
    },
    approved = TRUE,
    code_version = "v1"
  )
  expect_error(measure(f$lake, metric, record = FALSE), "optional")
  metric$input_columns <- "amount"
  expect_equal(measure(f$lake, metric, record = FALSE)$value, 10)
  metric$input_columns <- "absent"
  expect_error(
    measure(f$lake, metric, record = FALSE),
    "columns are missing"
  )
})

test_that("read-only attachments protect data and metadata while supporting analyses", {
  root <- tempfile("tidyweave-read-only-")
  lake <- open_lake(
    root,
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  on.exit({
    close_lake(lake)
    unlink(root, recursive = TRUE)
  })
  write_data(lake, data.frame(id = 1L, amount = 10), "orders")
  metric <- metric(
    "total",
    "orders",
    sum(amount, na.rm = TRUE),
    approved = TRUE,
    code_version = "v1"
  )
  measured <- measure(lake, metric)
  report_release(lake, "report", list(total = measured), "v1")
  tables <- c(
    "assets",
    "runs",
    "reports",
    "lineage_edges",
    "events",
    "schema_version"
  )
  before <- lapply(tables, function(x) registry(lake, x))
  close_lake(lake)
  lake <- open_lake(root, read_only = TRUE)
  expect_equal(measure(lake, metric)$value, 10)
  expect_equal(
    report_read(lake, "report", values_only = TRUE)$total$value,
    10
  )
  expect_error(measure(lake, metric, record = TRUE), class = "tw_read_only")
  expect_error(
    write_data(lake, data.frame(id = 2L), "other"),
    class = "tw_read_only"
  )
  expect_error(register(lake, metric), class = "tw_read_only")
  expect_error(
    report_release(lake, "another", list(total = measured), "v1"),
    class = "tw_read_only"
  )
  expect_error(DBI::dbExecute(
    lake$con,
    paste("DELETE FROM", meta(lake, "reports"))
  ))
  expect_identical(lapply(tables, function(x) registry(lake, x)), before)
  transient <- metric
  transient$id <- "transient"
  expect_equal(measure(lake, transient)$value, 10)
  expect_equal(nrow(registry(lake, "assets")), nrow(before[[1]]))
})

test_that("read-only opening never creates a missing lake", {
  root <- tempfile("tidyweave-absent-")
  expect_error(open_lake(root, read_only = TRUE), "must already exist")
  expect_false(dir.exists(root))
})

test_that("report retries ignore only volatile calculation times", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  metric <- reserve_metric()
  metric$dimensions <- c("company", "date")
  first <- measure(f$lake, metric, by = "date")
  initial <- report_release(f$lake, "monthly", list(total = first), "v1")
  saved <- registry(f$lake, "reports")
  second <- measure(f$lake, metric, by = "date")
  expect_no_error(
    retry <- report_release(
      f$lake,
      "monthly",
      list(total = second),
      "v1"
    )
  )
  expect_identical(initial, retry)
  expect_s3_class(retry$measures$total$values$date, "Date")
  expect_identical(registry(f$lake, "reports"), saved)
  expect_equal(report_read(f$lake, "monthly", TRUE)$total$value, 300)
  expect_identical(
    report_read(f$lake, "monthly")$measures$total$manifest$calculated_at,
    attr(first, "tw_manifest")$calculated_at
  )
  expect_error(
    report_release(f$lake, "monthly", list(total = second), "v2"),
    "different content"
  )
  expect_error(
    report_release(
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
  run(f$pipeline, f$lake)
  expect_error(
    report_release(
      f$lake,
      "monthly",
      list(total = measure(f$lake, metric)),
      "v1"
    ),
    "different content"
  )
})

test_that("legacy report values remain readable including missing groups", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  old <- list(
    id = "legacy",
    code_version = "v0",
    params = list(),
    measures = list(
      total = list(
        manifest = list(metric = "old", calculated_at = "2026-01-01"),
        values = data.frame(group = c("a", NA), value = c(2, 3))
      )
    )
  )
  insert_meta(
    f$lake,
    "reports",
    list(id = "legacy", created_at = now(), manifest = jencode(old))
  )
  expect_equal(
    report_read(f$lake, "legacy", TRUE)$total,
    tibble::tibble(group = c("a", NA), value = c(2, 3))
  )
  expect_error(report_read(f$lake, "absent"), class = "tw_no_report")
})


test_that("saved pre-read-only configurations remain executable", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  legacy <- f$pipeline
  legacy$config$read_only <- NULL
  expect_equal(run(legacy, f$lake)$status, "published")
})

test_that("custom metric groups are unique and repeated lineage is deduplicated", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  metric <- reserve_metric()
  measure(f$lake, metric)
  before <- registry(f$lake, "lineage_edges")
  measure(f$lake, metric)
  expect_identical(registry(f$lake, "lineage_edges"), before)
  metric$compute <- function(data, dimensions, params) {
    data.frame(company = c("a", "a"), value = c(1, 2))
  }
  metric$expr <- NULL
  metric$version <- "2.0.0"
  expect_error(
    measure(f$lake, metric, by = "company"),
    "one row per requested group"
  )
})


test_that("group order cannot change the identity of identical metric results", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  reverse <- FALSE
  metric <- metric(
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
  first <- measure(f$lake, metric, by = "company")
  reverse <- TRUE
  second <- measure(f$lake, metric, by = "company")
  expect_equal(first$company, c("a", "b"))
  expect_identical(
    attr(first, "tw_manifest")$result_hash,
    attr(second, "tw_manifest")$result_hash
  )
  report_release(f$lake, "ordered-report", list(total = first), "v1")
  expect_no_error(report_release(
    f$lake,
    "ordered-report",
    list(total = second),
    "v1"
  ))
})
