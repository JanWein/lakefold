test_that("minimal ingestion publishes an exact raw reference and schema", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  orders <- data.frame(id = 1:2, amount = c(25, 75))
  accepted <- ingest(orders, lake, quality = ~ amount >= 0)
  expect_s3_class(accepted, "tw_run_result")
  expect_equal(accepted$status, "published")
  expect_equal(accepted$asset, "orders")
  expect_equal(accepted$outputs$database, "lake")
  expect_equal(accepted$outputs$schema, "raw")
  expect_equal(accepted$outputs$asset, accepted$asset)
  expect_equal(accepted$outputs$release_id, accepted$release_id)
  expect_match(accepted$outputs$table, "^candidate_")
  expect_equal(
    accepted$outputs$table,
    resolve_release(lake, "orders", accepted$release_id)$table_name[[1]]
  )
  expect_equal(collect(accepted), tibble::as_tibble(orders))
  expect_equal(accepted$metadata$schema, c(id = "integer", amount = "numeric"))
  expect_equal(accepted$metadata$rows, 2)
  expect_equal(accepted$metadata$contract$required, character())
  expect_setequal(quality(accepted)$stage, c("ingest", "candidate"))
  expect_true(DBI::dbIsValid(lake$con))
})

test_that("native input failures never write raw and keep accepted releases", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  checks <- list(nonnegative = ~ amount >= 0)
  accepted <- ingest(
    data.frame(id = 1L, amount = 10),
    lake,
    "orders",
    quality = checks
  )
  blocked <- ingest(
    data.frame(id = 2L, amount = -1),
    lake,
    "orders",
    quality = checks,
    stop_on_failure = FALSE
  )
  expect_equal(blocked$status, "blocked")
  expect_equal(unique(quality(blocked)$stage), "ingest")
  expect_true(any(quality(blocked)$status == "failed"))
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("raw_", blocked$run_id))
  ))
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("candidate_", blocked$run_id))
  ))
  expect_true(all(file.exists(blocked$inputs$landed_path)))
  expect_equal(releases(lake, "orders")$release_id, accepted$release_id)
  expect_equal(collect(accepted)$amount, 10)
  expect_equal(registry(lake, "runs")$status, c("published", "blocked"))
  error <- tryCatch(
    ingest(data.frame(id = 3L, amount = -2), lake, "orders", quality = checks),
    tw_run_failed = identity
  )
  expect_s3_class(error, "tw_run_failed")
  expect_equal(error$result$status, "blocked")
})

test_that("file readers and callbacks run once against retained original bytes", {
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  path <- file.path(root, "orders.csv")
  utils::write.csv(data.frame(id = 1L, amount = 10), path, row.names = FALSE)
  reads <- checks <- 0L
  observed_path <- NULL
  reader <- function(path) {
    reads <<- reads + 1L
    observed_path <<- path
    utils::read.csv(path)
  }
  check <- function(data) {
    checks <<- checks + 1L
    data$amount >= 0
  }
  accepted <- ingest(path, lake, quality = check, reader = reader)
  expect_equal(accepted$asset, "orders")
  expect_equal(reads, 1L)
  expect_equal(checks, 1L)
  expect_equal(observed_path, accepted$inputs$landed_path[[1]])
  utils::write.csv(data.frame(id = 2L, amount = -10), path, row.names = FALSE)
  blocked <- ingest(
    path,
    lake,
    quality = check,
    reader = reader,
    stop_on_failure = FALSE
  )
  expect_equal(blocked$status, "blocked")
  expect_equal(reads, 2L)
  expect_equal(checks, 2L)
  expect_equal(
    readBin(blocked$inputs$landed_path[[1]], "raw", n = 10000),
    readBin(path, "raw", n = 10000)
  )
  expect_equal(collect(accepted)$amount, 10)
})

test_that("inferred schema failures are blocked before raw without locking a failed first schema", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  accepted <- ingest(data.frame(id = 1:2), lake, "orders")
  for (bad in list(
    data.frame(id = c("a", "b")),
    data.frame(id = 1L, extra = TRUE),
    data.frame(id = integer())
  )) {
    result <- ingest(bad, lake, "orders", stop_on_failure = FALSE)
    expect_equal(result$status, "blocked")
    expect_equal(unique(quality(result)$stage), "ingest")
    expect_false(DBI::dbExistsTable(
      lake$con,
      table_id("raw", paste0("raw_", result$run_id))
    ))
    expect_equal(
      resolve_release(lake, "orders")$release_id,
      accepted$release_id
    )
  }
  first <- ingest(
    data.frame(id = integer()),
    lake,
    "new_orders",
    stop_on_failure = FALSE
  )
  expect_equal(first$status, "blocked")
  next_delivery <- ingest(data.frame(id = "a"), lake, "new_orders")
  expect_equal(next_delivery$status, "published")
  expect_equal(collect(next_delivery)$id, "a")
})

test_that("source functions are acquired once and default runs reevaluate captured state", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  calls <- checks <- 0L
  value <- 1L
  allowed <- TRUE
  source <- function() {
    calls <<- calls + 1L
    data.frame(id = value)
  }
  check <- function(data) {
    checks <<- checks + 1L
    allowed
  }
  first <- ingest(source, lake, "orders", quality = check)
  expect_equal(c(calls, checks), c(1L, 1L))
  value <- 2L
  second <- ingest(source, lake, "orders", quality = check)
  expect_equal(c(calls, checks), c(2L, 2L))
  expect_equal(collect(first)$id, 1L)
  expect_equal(collect(second)$id, 2L)
  allowed <- FALSE
  blocked <- ingest(
    source,
    lake,
    "orders",
    quality = check,
    stop_on_failure = FALSE
  )
  expect_equal(blocked$status, "blocked")
  expect_equal(c(calls, checks), c(3L, 3L))
  expect_equal(resolve_release(lake, "orders")$release_id, second$release_id)
})

test_that("explicit contracts retain keys and nonnull rules and accept concise types", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  specification <- contract(
    columns = list(id = integer(), amount = double()),
    key = "id"
  )
  accepted <- ingest(
    data.frame(id = 1:2, amount = c(10, 20)),
    lake,
    "orders",
    specification
  )
  candidate <- quality(accepted)
  expect_true(all(
    c("ingest", "candidate") %in%
      candidate$stage[grepl("key|not_null", candidate$rule)]
  ))
  for (bad in list(
    data.frame(id = c(1L, 1L), amount = c(10, 20)),
    data.frame(id = 3L, amount = NA_real_)
  )) {
    result <- ingest(
      bad,
      lake,
      "orders",
      specification,
      stop_on_failure = FALSE
    )
    expect_equal(result$status, "blocked")
    expect_equal(unique(quality(result)$stage), "ingest")
  }
  concise <- ingest(
    data.frame(id = 1L),
    lake,
    "concise",
    contract = c(id = "integer")
  )
  expect_equal(concise$status, "published")
  prototypes <- ingest(
    data.frame(id = 1L),
    lake,
    "prototypes",
    contract = list(id = integer())
  )
  expect_equal(prototypes$status, "published")
})

test_that("warning-only input checks accept data and are not rerun on the candidate", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  calls <- 0L
  advisory <- quality_rule(
    "advisory",
    function(data) {
      calls <<- calls + 1L
      FALSE
    },
    severity = "warning"
  )
  result <- ingest(data.frame(id = 1L), lake, "orders", quality = advisory)
  expect_equal(result$status, "published")
  expect_equal(calls, 1L)
  checks <- quality(result)
  expect_equal(checks$stage[checks$rule == "advisory"], "ingest")
  expect_equal(checks$status[checks$rule == "advisory"], "warning")
})

test_that("config ownership and exact result collection survive later releases", {
  root <- withr::local_tempdir()
  config <- lake_config(
    registry_duckdb(file.path(root, "lake.db")),
    storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  first <- ingest(data.frame(id = 1L), config, "orders")
  expect_null(first$output_lake)
  expect_equal(first$output_config, config)
  second <- ingest(data.frame(id = 2L), config, "orders")
  expect_equal(collect(first)$id, 1L)
  expect_equal(collect(second)$id, 2L)
  lake <- connect_lake(config)
  withr::defer(close_lake(lake))
  expect_equal(resolve_release(lake, "orders")$release_id, second$release_id)
})

test_that("database source factories open once and close before returning", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  calls <- 0L
  source_con <- NULL
  factory <- function() {
    calls <<- calls + 1L
    source_con <<- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
    DBI::dbWriteTable(source_con, "delivery", data.frame(id = 1:2))
    source_con
  }
  result <- ingest(source_database(factory, table = "delivery"), lake, "orders")
  expect_equal(calls, 1L)
  expect_false(DBI::dbIsValid(source_con))
  expect_equal(collect(result)$id, 1:2)
  expect_match(result$inputs$original_name, "rds$")
})

test_that("pointblank builds and checks once before any raw write", {
  skip_if_not_installed("pointblank")
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  calls <- 0L
  check <- pointblank_checks("amounts", function(data) {
    calls <<- calls + 1L
    pointblank::create_agent(data) |>
      pointblank::col_vals_gte(columns = "amount", value = 0)
  })
  first <- ingest(data.frame(amount = 10), lake, "orders", quality = check)
  expect_equal(first$status, "published")
  expect_equal(calls, 1L)
  blocked <- ingest(
    data.frame(amount = -1),
    lake,
    "orders",
    quality = check,
    stop_on_failure = FALSE
  )
  expect_equal(blocked$status, "blocked")
  expect_equal(calls, 2L)
  expect_equal(unique(quality(blocked)$stage), "ingest")
  expect_true("pointblank" %in% quality(blocked)$engine)
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("raw_", blocked$run_id))
  ))
  expect_equal(resolve_release(lake, "orders")$release_id, first$release_id)
})

test_that("cache is explicit and returns original checked contract evidence", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  calls <- 0L
  check <- function(data) {
    calls <<- calls + 1L
    TRUE
  }
  data <- data.frame(id = 1L)
  expect_error(ingest(data, lake, "orders", cache = TRUE), "code_version")
  first <- ingest(
    data,
    lake,
    "orders",
    quality = check,
    code_version = "v1",
    cache = TRUE
  )
  second <- ingest(
    data,
    lake,
    "orders",
    quality = check,
    code_version = "v1",
    cache = TRUE
  )
  expect_equal(second$status, "cached")
  expect_equal(second$release_id, first$release_id)
  expect_equal(calls, 1L)
  expect_equal(second$metadata$contract$id, first$metadata$contract$id)
  expect_true(nrow(quality(second)) > 0L)
  expect_equal(collect(second), tibble::as_tibble(data))
})

test_that("reader failure retains one durable run and immutable original", {
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  path <- file.path(root, "broken.txt")
  writeLines("invalid delivery", path)
  result <- ingest(
    path,
    lake,
    reader = function(path) stop("cannot parse"),
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "error")
  expect_equal(nrow(registry(lake, "runs")), 1L)
  expect_true(file.exists(result$inputs$landed_path[[1]]))
  expect_equal(readLines(result$inputs$landed_path[[1]]), "invalid delivery")
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("raw_", result$run_id))
  ))
})

test_that("pinned release sources retain their exact lineage in ingestion", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  original <- ingest(data.frame(id = 1L), lake, "original")
  ingest(data.frame(id = 2L), lake, "original")
  result <- ingest(
    source_release(lake, "original", original$release_id),
    lake,
    "orders"
  )
  expect_equal(collect(result)$id, 1L)
  reference <- result$inputs[result$inputs$source == "original", ]
  expect_equal(reference$source_version, original$release_id)
  edges <- registry(lake, "lineage_edges")
  expect_true(any(
    edges$from_id == "original" &
      edges$from_version == original$release_id &
      edges$to_id == "orders"
  ))
})

test_that("single local Parquet input keeps original bytes before checking", {
  skip_if_not_installed("arrow")
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  path <- file.path(root, "orders.parquet")
  arrow::write_parquet(data.frame(id = 1L, amount = -1), path)
  result <- ingest(path, lake, quality = ~ amount >= 0, stop_on_failure = FALSE)
  expect_equal(result$status, "blocked")
  expect_equal(result$inputs$original_name, "orders.parquet")
  expect_equal(
    readBin(result$inputs$landed_path[[1]], "raw", n = 10000),
    readBin(path, "raw", n = 10000)
  )
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("raw_", result$run_id))
  ))
})

test_that("ingestion refuses invalid execution options and approved asset reuse", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  data <- data.frame(id = 1L)
  expect_error(ingest(data, lake, business_date = 1:2), "business_date")
  expect_error(ingest(data, lake, cahe = TRUE), "Unknown ingestion option")
  approved <- write_data(lake, data, "orders")
  expect_error(ingest(data, lake, "orders"), "distinct ingestion name")
  expect_equal(resolve_release(lake, "orders")$release_id, approved$release_id)
})

test_that("product ingestion retains its input contract and quality before RAW", {
  config <- lake_config(path = file.path(withr::local_tempdir(), "lake"))
  orders <- data.frame(id = 1L, amount = 10)
  specification <- product("orders", orders, code_version = "delivery-v1") |>
    add_contract(contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    )) |>
    add_quality(~ amount >= 0)
  accepted <- specification |> ingest(to = config)
  expect_identical(accepted$asset, "orders")
  expect_equal(collect(accepted), tibble::as_tibble(orders))
  expect_identical(accepted$metadata$contract$key, "id")
  expect_identical(accepted$metadata$definition$code_version, "delivery-v1")
  bad <- product(
    "orders",
    data.frame(id = 2L, amount = -1),
    code_version = "delivery-v1"
  ) |>
    add_contract(specification$contract) |>
    add_quality(~ amount >= 0)
  rejected <- bad |> ingest(to = config, stop_on_failure = FALSE)
  expect_identical(rejected$status, "blocked")
  expect_identical(unique(quality(rejected)$stage), "ingest")
  lake <- connect_lake(config)
  withr::defer(close_lake(lake))
  expect_false(DBI::dbExistsTable(
    lake$con,
    table_id("raw", paste0("raw_", rejected$run_id))
  ))
  expect_identical(
    resolve_release(lake, "orders")$release_id[[1]],
    accepted$release_id
  )
})

test_that("unsupported product ingestion fails before source or destination I/O", {
  root <- file.path(withr::local_tempdir(), "not-created")
  config <- lake_config(path = root)
  calls <- 0L
  source <- function() {
    calls <<- calls + 1L
    data.frame(id = 1L)
  }
  plain <- product("orders", source)
  transformed <- plain |> add_transform(identity)
  multiple <- plain |> add_source(data.frame(id = 2L))
  nested <- product("nested", plain)
  targeted <- plain |> set_target(config)
  cataloged <- plain |> add_catalog(function(...) invisible(NULL))
  for (invalid in list(product("empty"), transformed, multiple, nested)) {
    expect_error(ingest(invalid, to = config), "one ordinary product source")
  }
  for (invalid in list(targeted, cataloged)) {
    expect_error(
      ingest(invalid, to = config),
      "Remove product targets and catalogs"
    )
  }
  expect_error(
    ingest(plain, to = config, contract = c(id = "integer")),
    "add_contract"
  )
  expect_error(ingest(plain, to = config, reader = readRDS), "add_source")
  expect_error(
    ingest(plain, to = config, name = "different"),
    "own ingestion name"
  )
  expect_equal(calls, 0L)
  expect_false(dir.exists(root))
})

test_that("data-first ingestion has a local default and checks before creating it", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  orders <- data.frame(id = 1L)
  expect_error(ingest(orders, quality = ~id ~ 1), "one-sided")
  expect_false(dir.exists("tidyweave"))
  accepted <- orders |> ingest()
  expect_identical(accepted$asset, "orders")
  expect_identical(accepted$backend, "duckdb")
  expect_equal(collect(accepted)$id, 1L)
  elsewhere <- orders |> ingest(to = "other-lake")
  expect_equal(collect(elsewhere)$id, 1L)
  readonly <- lake_config(path = "not-created", read_only = TRUE)
  expect_error(ingest(orders, to = readonly), "writable destination")
  expect_false(dir.exists("not-created"))
})
