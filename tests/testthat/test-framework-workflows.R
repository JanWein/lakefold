test_that("simple partition writes retain months and delivery evidence", {
  f <- fixture()
  on.exit(cleanup(f))
  write <- function(date, amount) {
    dl_write(
      f$lake,
      data.frame(month = as.Date(date), amount = amount),
      "monthly",
      partition_by = "month",
      business_date = date
    )
  }
  august <- write("2026-08-31", 350)
  september <- write("2026-09-30", 390)
  corrected <- write("2026-08-31", 370)
  expect_equal(dl_read(f$lake, "monthly")$amount, c(390, 370))
  contract <- dl_contract(
    "delivery",
    columns = c(month = "Date", amount = "numeric")
  )
  due <- as.POSIXct("2026-10-01", tz = "UTC")
  check <- function(...) {
    dl_check_delivery(
      f$lake,
      "monthly",
      contract,
      "2026-09-30",
      due,
      at = due,
      ...
    )
  }
  expect_error(
    check(record = FALSE, notify = function(event) NULL),
    "require record"
  )
  expect_equal(check()$status, "received")
  expect_equal(check()$release_id, corrected$release_id)
  expect_equal(dl_read(f$lake, "monthly", august$release_id)$amount, 350)
  dl_write(
    f$lake,
    data.frame(month = as.Date("2026-08-31"), amount = 375),
    "monthly",
    business_date = "2026-08-31"
  )
  expect_equal(check()$status, "missing")
  expect_equal(check(date_column = "month")$status, "missing")
  expect_equal(nrow(dl_read(f$lake, "monthly", september$release_id)), 2)
})

test_that("automatic numeric schemas widen without weakening explicit integer contracts", {
  f <- fixture()
  on.exit(cleanup(f))
  legacy <- automatic_schema("legacy", c(id = "integer", amount = "integer"))
  first <- dl_ingest_data(
    f$lake,
    data.frame(id = 1L, amount = 10L),
    legacy,
    "legacy",
    code_version = "old"
  )
  old <- dl_registry(f$lake, "assets")
  second <- dl_write(f$lake, data.frame(id = 1L, amount = 10.5), "legacy")
  expect_equal(second$status, "published")
  expect_equal(dl_read(f$lake, "legacy", first$release_id)$amount, 10L)
  current <- dl_registry(f$lake, "assets")
  expect_true(all(old$fingerprint %in% current$fingerprint))
  strict <- dl_contract(
    "strict",
    columns = c(id = "integer", amount = "integer")
  )
  result <- dl_write(
    f$lake,
    data.frame(id = 1L, amount = 10.5),
    "strict",
    contract = strict,
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
})

test_that("quoted column names survive writes, contracts, grouping and comparisons", {
  f <- fixture()
  on.exit(cleanup(f))
  data <- data.frame(
    "Record ID" = c(1L, 2L),
    "Reserve amount" = c(10, 20),
    "group\"name" = c("a", "b"),
    check.names = FALSE
  )
  contract <- dl_contract(
    "quoted",
    columns = c(
      "Record ID" = "integer",
      "Reserve amount" = "numeric",
      "group\"name" = "character"
    ),
    key = "Record ID"
  )
  dl_write(f$lake, data, "quoted", contract = contract)
  expect_identical(names(dl_read(f$lake, "quoted")), names(data))
  data[["Reserve amount"]][[1]] <- 12
  dl_write(f$lake, data, "quoted", contract = contract)
  metric <- dl_metric(
    "quoted.total",
    "quoted",
    sum(`Reserve amount`, na.rm = TRUE),
    dimensions = "group\"name",
    approved = TRUE,
    code_version = "v1"
  )
  expect_equal(dl_measure(f$lake, metric, by = "group\"name")$value, c(12, 20))
  diff <- dl_compare(f$lake, "quoted")
  expect_equal(diff$counts[["changed"]], 1)
  expect_equal(diff$numeric_summary$difference, 2)
  expect_equal(diff$changed$after[["Reserve amount"]], 12)
})

test_that("release comparisons count all differences while bounding previews", {
  f <- fixture()
  on.exit(cleanup(f))
  before <- data.frame(id = 1:5, amount = c(10, 20, NA, 40, 50))
  after <- data.frame(
    id = c(1L, 3L, 4L, 6L, 7L),
    amount = c(11, NA, 41, 60, 70)
  )
  a <- dl_write(f$lake, before, "orders")
  b <- dl_write(f$lake, after, "orders")
  diff <- dl_compare(f$lake, "orders", key = "id", limit = 1)
  expect_equal(
    diff$counts,
    c(added = 2, removed = 2, changed = 2, unchanged = 1)
  )
  expect_equal(nrow(diff$added), 1)
  expect_equal(nrow(diff$changed$before), 1)
  expect_identical(diff$changed$before$id, diff$changed$after$id)
  expect_equal(diff$numeric_summary$difference, 62)
  expect_equal(diff$numeric_summary$missing_before, 1)
  reverse <- dl_compare(
    f$lake,
    "orders",
    from = b$release_id,
    to = a$release_id,
    key = "id",
    limit = Inf
  )
  expect_equal(reverse$numeric_summary$difference, -62)
  expect_equal(nrow(reverse$added), 2)
  expect_error(dl_compare(f$lake, "orders"), "Supply key")
  expect_error(dl_compare(f$lake, "orders", key = "id", limit = -1), "limit")
  same <- dl_compare(
    f$lake,
    "orders",
    from = a$release_id,
    to = a$release_id,
    key = "id",
    limit = 0
  )
  expect_equal(same$counts[["unchanged"]], 5)
  expect_equal(nrow(same$changed$before), 0)
})

test_that("comparisons reject ambiguous keys and report schema changes", {
  f <- fixture()
  on.exit(cleanup(f))
  a <- dl_write(f$lake, data.frame(id = c(1L, 1L), amount = 1:2), "duplicates")
  b <- dl_write(f$lake, data.frame(id = 1:2, amount = 1:2), "duplicates")
  expect_error(
    dl_compare(f$lake, "duplicates", key = "id"),
    "unique, non-missing"
  )
  contract <- dl_contract(
    "schema1",
    columns = c(id = "integer", amount = "numeric")
  )
  dl_write(
    f$lake,
    data.frame(id = 1L, amount = 10),
    "schema",
    contract = contract
  )
  contract <- dl_contract(
    "schema2",
    columns = c(id = "integer", amount = "numeric", label = "character")
  )
  dl_write(
    f$lake,
    data.frame(id = 1L, amount = 10, label = "a"),
    "schema",
    contract = contract
  )
  diff <- dl_compare(f$lake, "schema", key = "id")
  expect_equal(diff$counts[["changed"]], 1)
  expect_equal(diff$schema$column, "label")
})

test_that("source functions fetch once and archive the received data", {
  f <- fixture()
  on.exit(cleanup(f))
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    data.frame(id = 1L, amount = calls)
  }
  first <- dl_write(f$lake, fetch, "api_orders")
  expect_equal(calls, 1)
  dl_write(f$lake, fetch, "api_orders")
  expect_equal(calls, 2)
  expect_equal(dl_read(f$lake, "api_orders")$amount, 2)
  expect_equal(dl_read(f$lake, "api_orders", first$release_id)$amount, 1)
  inputs <- dl_registry(f$lake, "inputs")
  expect_true(all(file.exists(inputs$landed_path)))
  expect_error(dl_write(f$lake, fetch), "Supply name")
  expect_error(
    dl_write(f$lake, function() NULL, "invalid"),
    "return a data frame"
  )
})

test_that("quality exceptions are available locally without entering registry text", {
  f <- fixture()
  on.exit(cleanup(f))
  contract <- dl_contract(
    "broken",
    columns = c(id = "integer"),
    rules = list(
      dl_rule("broken_rule", function(data) stop("private diagnostic example"))
    )
  )
  quality <- dl_validate(data.frame(id = 1L), contract, keep_errors = TRUE)
  expect_match(
    conditionMessage(dl_quality_errors(quality)$broken_rule),
    "private diagnostic"
  )
  expect_length(
    dl_quality_errors(dl_validate(data.frame(id = 1L), contract)),
    0
  )
  result <- dl_write(
    f$lake,
    data.frame(id = 1L),
    "broken",
    contract = contract,
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
  persist_quality(f$lake, "local-diagnostic", contract, quality)
  expect_false(any(grepl(
    "private diagnostic",
    unlist(dl_registry(f$lake, "quality_results")),
    fixed = TRUE
  )))
})

test_that("recovery previews and protects live writers", {
  f <- fixture()
  on.exit(cleanup(f))
  run <- new_run(f$lake, "interrupted", "orders", "hash", "v1")
  plan <- dl_recover(f$lake, run_ids = run)
  expect_equal(plan$action, "would_mark_error")
  expect_equal(dl_registry(f$lake, "runs")$status, "running")
  if (nzchar(writer_identity()$boot)) {
    expect_equal(plan$writer, "alive")
    expect_error(
      dl_recover(f$lake, run_ids = run, dry_run = FALSE, writer_stopped = TRUE),
      "still alive"
    )
  } else {
    expect_equal(plan$writer, "unknown")
  }
  exec(
    f$lake,
    paste("DELETE FROM", meta(f$lake, "run_owners"), "WHERE run_id = ?"),
    list(run)
  )
  expect_error(
    dl_recover(f$lake, run_ids = run, dry_run = FALSE),
    "liveness is unknown"
  )
  expect_equal(
    dl_recover(
      f$lake,
      run_ids = run,
      dry_run = FALSE,
      writer_stopped = TRUE
    )$action,
    "marked_error"
  )
  expect_equal(dl_registry(f$lake, "runs")$status, "error")
  expect_error(dl_recover(f$lake, run_ids = run), "existing running job")
  expect_error(dl_recover(f$lake, dry_run = FALSE), "explicitly")
})

test_that("staging recovery enables retry while preserving published releases", {
  f <- fixture()
  on.exit(cleanup(f))
  published <- dl_write(f$lake, data.frame(id = 1L), "orders")
  slot <- file.path(f$lake$config$landing, ".lakefold-staging", "orders")
  dir.create(slot, recursive = TRUE)
  writeLines("orphan", file.path(slot, "delivery.rds"))
  expect_error(
    dl_write(f$lake, data.frame(id = 2L), "orders"),
    "Staging already exists"
  )
  expect_equal(dl_recover(f$lake, staging_assets = "orders")$writer, "unknown")
  expect_equal(
    dl_recover(
      f$lake,
      staging_assets = "orders",
      dry_run = FALSE,
      writer_stopped = TRUE
    )$action,
    "removed_staging"
  )
  expect_equal(
    dl_write(f$lake, data.frame(id = 2L), "orders")$status,
    "published"
  )
  expect_equal(dl_read(f$lake, "orders", published$release_id)$id, 1L)
})

test_that("product builders can explicitly bypass cached releases", {
  f <- fixture()
  on.exit(cleanup(f))
  dl_run(f$pipeline, f$lake)
  multiplier <- 1
  product <- dl_product(
    "scaled",
    c(input = "risk.validated"),
    build = function(inputs) {
      dplyr::mutate(inputs$input, reserve = reserve * !!multiplier)
    },
    contract = f$contract,
    code_version = "external-state-v1"
  )
  first <- dl_build(f$lake, product)
  multiplier <- 2
  expect_equal(dl_build(f$lake, product)$status, "cached")
  expect_equal(dl_build(f$lake, product, cache = FALSE)$status, "published")
  expect_equal(sum(dl_read(f$lake, "scaled")$reserve), 600)
  expect_equal(sum(dl_read(f$lake, "scaled", first$release_id)$reserve), 300)
})

test_that("schema 2 migration retains history and read-only opening never migrates", {
  f <- fixture()
  on.exit(cleanup(f))
  first <- dl_write(f$lake, data.frame(id = 1L), "orders")
  original <- dl_registry(f$lake, "assets")
  exec(f$lake, paste("DELETE FROM", meta(f$lake, "schema_version")))
  insert_meta(f$lake, "schema_version", list(version = 2L, applied_at = now()))
  exec(f$lake, paste("DROP TABLE", meta(f$lake, "run_owners")))
  config <- f$lake$config
  dl_close(f$lake)
  expect_error(
    dl_connect(config, read_only = TRUE),
    "Unsupported registry version"
  )
  f$lake <- dl_connect(config)
  expect_equal(dl_registry(f$lake, "schema_version")$version, c(2L, 3L))
  expect_identical(dl_registry(f$lake, "assets"), original)
  expect_equal(dl_read(f$lake, "orders", first$release_id)$id, 1L)
  registry_init(f$lake)
  expect_equal(dl_registry(f$lake, "schema_version")$version, c(2L, 3L))
  expect_equal(nrow(dl_registry(f$lake, "run_owners")), 0)
  expect_identical(dl_registry(f$lake, "run"), dl_registry(f$lake, "runs"))
  expect_identical(dl_registry(f$lake, "ru"), dl_registry(f$lake, "runs"))
})
