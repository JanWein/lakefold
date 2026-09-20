test_that("the minimal workflow survives closing and reopening", {
  root <- withr::local_tempdir()
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  orders <- data.frame(
    id = 1:2,
    amount = c(10, NA_real_),
    date = as.Date(c("2026-01-01", "2026-01-02"))
  )
  first <- write_data(lake, orders)
  expect_equal(first$status, "published")
  expect_equal(read_release(lake, "orders"), tibble::as_tibble(orders))
  expect_s3_class(read_release(lake, "orders", lazy = TRUE), "tbl_sql")
  expect_equal(freshness(lake)$freshness, "unknown")
  close_lake(lake)
  lake <- open_lake(root)
  expect_equal(lake$config$backend, "duckdb")
  expect_equal(write_data(lake, orders)$status, "cached")
  expect_equal(read_release(lake, "orders", release = first$release_id)$id, 1:2)
})

test_that("changed and empty deliveries cannot replace a successful schema", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  orders <- data.frame(id = 1:2)
  write_data(lake, orders)
  for (bad in list(
    data.frame(id = c("a", "b")),
    data.frame(id = 1L, extra = TRUE),
    data.frame(id = integer())
  )) {
    result <- write_data(lake, bad, "orders", stop_on_failure = FALSE)
    expect_equal(result$status, "blocked")
    expect_equal(read_release(lake, "orders")$id, 1:2)
    expect_equal(any(result$quality$status == "failed"), TRUE)
  }
})

test_that("a failed first delivery does not lock the future schema", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  result <- write_data(
    lake,
    data.frame(id = integer()),
    "orders",
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
  expect_equal(
    write_data(lake, data.frame(id = "a"), "orders")$status,
    "published"
  )
  expect_equal(read_release(lake, "orders")$id, "a")
})

test_that("writing an older payload makes it current again", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  first <- write_data(lake, data.frame(id = 1L), "orders")
  second <- write_data(lake, data.frame(id = 2L), "orders")
  third <- write_data(lake, data.frame(id = 1L), "orders")
  expect_equal(third$status, "published")
  expect_equal(read_release(lake, "orders")$id, 1L)
  expect_equal(read_release(lake, "orders", release = second$release_id)$id, 2L)
  expect_equal(third$release_id == first$release_id, FALSE)
  expect_equal(write_data(lake, data.frame(id = 1L), "orders")$status, "cached")
})

test_that("file defaults preserve original bytes and support CSV TSV and RDS", {
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  data <- data.frame(id = 1:2, value = c(10.5, 20.5))
  csv <- file.path(root, "orders.csv")
  tsv <- file.path(root, "tabular.tsv")
  rds <- file.path(root, "snapshot.rds")
  utils::write.csv(data, csv, row.names = FALSE)
  utils::write.table(data, tsv, sep = "\t", row.names = FALSE)
  saveRDS(data, rds)
  for (path in c(csv, tsv, rds)) {
    expect_equal(write_data(lake, path)$status, "published")
    expect_equal(write_data(lake, path)$status, "cached")
    name <- tools::file_path_sans_ext(basename(path))
    expect_equal(read_release(lake, name), tibble::as_tibble(data))
  }
  inputs <- registry(lake, "inputs")
  expect_setequal(
    inputs$original_name,
    c("orders.csv", "tabular.tsv", "snapshot.rds")
  )
  landed <- inputs$landed_path[inputs$original_name == "orders.csv"][[1]]
  expect_equal(
    readBin(landed, "raw", n = file.info(landed)$size),
    readBin(csv, "raw", n = file.info(csv)$size)
  )
})

test_that("explicit contracts can add rules but cannot be silently dropped", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  data <- data.frame(id = 1:2)
  write_data(lake, data, "orders")
  contract <- contract(
    "orders.checked",
    columns = c(id = "integer"),
    key = "id"
  )
  expect_equal(write_data(lake, data, "orders", contract)$status, "published")
  bad <- write_data(
    lake,
    data.frame(id = c(1L, 1L)),
    "orders",
    contract,
    stop_on_failure = FALSE
  )
  expect_equal(bad$status, "blocked")
  expect_snapshot(error = TRUE, write_data(lake, data, "orders"))
})

test_that("custom rule closures are re-evaluated unless explicitly versioned", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  allowed <- TRUE
  contract <- contract(
    "checked",
    columns = c(id = "integer"),
    rules = list(quality_rule("external_state", function(data) allowed))
  )
  data <- data.frame(id = 1L)
  expect_equal(write_data(lake, data, "orders", contract)$status, "published")
  allowed <- FALSE
  expect_equal(
    write_data(lake, data, "orders", contract, stop_on_failure = FALSE)$status,
    "blocked"
  )
  allowed <- TRUE
  expect_equal(
    write_data(
      lake,
      data,
      "orders",
      contract,
      code_version = "checked-v1"
    )$status,
    "published"
  )
  expect_equal(
    write_data(
      lake,
      data,
      "orders",
      contract,
      code_version = "checked-v1"
    )$status,
    "cached"
  )
  expect_snapshot(
    error = TRUE,
    write_data(lake, data, "orders", contract, cache = TRUE)
  )
})

test_that("custom file readers use archived bytes and changing captured values", {
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  path <- file.path(root, "input.txt")
  writeLines("original", path)
  value <- 1L
  reader <- function(path) {
    stopifnot(readLines(path) == "original")
    data.frame(id = value)
  }
  expect_equal(write_data(lake, path, reader = reader)$status, "published")
  value <- 2L
  expect_equal(write_data(lake, path, reader = reader)$status, "published")
  expect_equal(read_release(lake, "input")$id, 2L)
})

test_that("reopening refuses an accidental backend switch", {
  root <- withr::local_tempdir()
  lake <- open_lake(root)
  close_lake(lake)
  expect_snapshot(error = TRUE, open_lake(root, backend = "ducklake"))
})

test_that("existing unmarked catalogs are not adopted implicitly", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "landing"))
  expect_snapshot(error = TRUE, open_lake(root))
})

test_that("arbitrary nonempty folders are left untouched", {
  root <- withr::local_tempdir()
  writeLines("existing custom catalog", file.path(root, "custom.db"))
  expect_snapshot(error = TRUE, open_lake(root))
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "custom.db")
  expect_equal(
    readLines(file.path(root, "custom.db")),
    "existing custom catalog"
  )
})

test_that("a blocked first contracted run still requires a contract after reopen", {
  root <- withr::local_tempdir()
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  contract <- contract("checked", columns = c(id = "integer"), key = "id")
  result <- write_data(
    lake,
    data.frame(id = c(1L, 1L)),
    "orders",
    contract,
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
  close_lake(lake)
  lake <- open_lake(root)
  expect_snapshot(error = TRUE, write_data(lake, data.frame(id = 1L), "orders"))
  expect_equal(nrow(releases(lake, "orders")), 0L)
  expect_equal(
    write_data(lake, data.frame(id = 1L), "orders", contract)$status,
    "published"
  )
})

test_that("a blocked contract upgrade cannot fall back to the automatic schema", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  write_data(lake, data.frame(id = 1L), "orders")
  contract <- contract("checked", columns = c(id = "integer"), key = "id")
  result <- write_data(
    lake,
    data.frame(id = c(1L, 1L)),
    "orders",
    contract,
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
  expect_snapshot(error = TRUE, write_data(lake, data.frame(id = 1L), "orders"))
  expect_equal(read_release(lake, "orders")$id, 1L)
})

test_that("a data expression needs a deliberate asset name", {
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  expect_snapshot(error = TRUE, write_data(lake, data.frame(id = 1L)))
})

test_that("contract drafts keep review explicit with optional metadata", {
  draft <- contract_from(data.frame(id = 1:2), "orders")
  contract <- contract_confirm(draft)
  expect_equal(contract$owner, "")
  expect_equal(contract$grain, "")
  expect_equal(contract$columns, list(id = "integer"))
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  expect_snapshot(
    error = TRUE,
    write_data(lake, data.frame(id = 1L), "orders", contract = draft)
  )
})

test_that("the simple entry point also works with DuckLake", {
  skip_if(Sys.getenv("TIDYWEAVE_TEST_DUCKLAKE") != "true")
  root <- withr::local_tempdir()
  lake <- open_lake(root, backend = "ducklake")
  withr::defer(close_lake(lake))
  orders <- data.frame(id = 1:2)
  write_data(lake, orders)
  close_lake(lake)
  lake <- open_lake(root)
  expect_equal(lake$config$backend, "ducklake")
  expect_equal(write_data(lake, orders)$status, "cached")
  expect_equal(read_release(lake, "orders")$id, 1:2)
})
