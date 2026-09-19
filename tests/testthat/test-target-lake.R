test_that("native and lake targets run the same transformations and quality rules", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- dl_open(
    file.path(root, "lake"),
    backend = Sys.getenv("DATALOOM_TEST_BACKEND", "duckdb")
  )
  withr::defer(dl_close(lake))
  received <- NULL
  product <- dl_product("orders") |>
    dl_add_source(data.frame(id = 1:2, amount = c(10, 20))) |>
    dl_add_transform(
      function(data) transform(data, amount = amount * 2),
      "double"
    ) |>
    dl_add_contract(c(id = "integer", amount = "numeric")) |>
    dl_add_quality(~ amount > 0) |>
    dl_add_catalog(function(metadata) received <<- metadata)
  native <- dl_run(product)
  persisted <- dl_run(product |> dl_add_target(lake))
  expect_equal(dl_collect(native), dl_collect(persisted))
  expect_equal(persisted$status, "published")
  expect_equal(received$rows, 2)
  expect_equal(DBI::dbIsValid(lake$con), TRUE)
  expect_equal(persisted$quality$status, native$quality$status)
  expect_equal(nrow(persisted$inputs), 1L)
  expect_equal(nrow(persisted$metadata$lineage), 2L)
  expect_equal(file.exists(persisted$inputs$landed_path), TRUE)
  expect_equal(readRDS(persisted$inputs$landed_path)$amount, c(10, 20))
})

test_that("automatic contracts are inferred after transforms and preserve schemas and rules", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- dl_open(file.path(root, "lake"))
  withr::defer(dl_close(lake))
  make <- function(data) {
    dl_product("orders") |>
      dl_add_source(data) |>
      dl_add_transform(function(data) data.frame(total = sum(data$amount))) |>
      dl_add_quality(~ total >= 0) |>
      dl_add_target(lake)
  }
  first <- dl_run(make(data.frame(amount = c(10, 20))))
  expect_equal(dl_collect(first)$total, 30)
  second <- dl_run(make(data.frame(amount = c(20, 20))))
  expect_equal(dl_collect(second)$total, 40)
  blocked <- dl_run(make(data.frame(amount = -10)), stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(dl_read(lake, "orders")$total, 40)
  expect_equal(dl_collect(first)$total, 30)
  unguarded <- dl_product("orders") |>
    dl_add_source(data.frame(total = 50)) |>
    dl_add_target(lake)
  expect_equal(dl_run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_snapshot(
    error = TRUE,
    dl_write(lake, data.frame(total = 50), "orders")
  )
})

test_that("file publication archives original bytes and records transform definitions", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  path <- file.path(root, "orders.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  product <- dl_product("orders") |>
    dl_add_source(path) |>
    dl_add_transform(
      function(data) transform(data, amount = id * 10),
      "add_amount"
    )
  result <- dl_publish(product, to = file.path(root, "lake"))
  expect_equal(dl_collect(result)$amount, c(10, 20))
  expect_identical(
    readBin(result$inputs$landed_path, "raw", n = file.info(path)$size),
    readBin(path, "raw", n = file.info(path)$size)
  )
  lake <- dl_open(file.path(root, "lake"), read_only = TRUE)
  withr::defer(dl_close(lake))
  definitions <- dl_registry(lake, "assets")
  expect_equal(
    any(grepl("add_amount", definitions$definition, fixed = TRUE)),
    TRUE
  )
})

test_that("partition targets validate retained partitions and preserve published history", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- dl_open(
    file.path(root, "lake"),
    backend = Sys.getenv("DATALOOM_TEST_BACKEND", "duckdb")
  )
  withr::defer(dl_close(lake))
  contract <- dl_contract(
    "orders",
    columns = c(id = "integer", month = "character", amount = "numeric"),
    key = c("id", "month")
  )
  make <- function(month, amount) {
    dl_product("orders") |>
      dl_add_source(data.frame(id = 1L, month = month, amount = amount)) |>
      dl_add_contract(contract) |>
      dl_add_quality(~ amount >= 0) |>
      dl_add_target(dl_target_lake(lake, partition_by = "month"))
  }
  first <- dl_run(make("August", 10))
  second <- dl_run(make("September", 20))
  expect_equal(nrow(dl_collect(second)), 2L)
  expect_equal(sum(dl_collect(second)$amount), 30)
  expect_equal(
    dl_run(make("August", -1), stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_equal(sum(dl_read(lake, "orders")$amount), 30)
  expect_equal(nrow(dl_collect(first)), 1L)
})

test_that("explicit contracts and versioned definitions cannot be silently weakened", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- dl_open(file.path(root, "lake"))
  withr::defer(dl_close(lake))
  product <- dl_product("orders", version = "1", code_version = "v1") |>
    dl_add_source(data.frame(id = 1L)) |>
    dl_add_contract(c(id = "integer")) |>
    dl_add_target(lake)
  first <- dl_run(product)
  expect_equal(dl_run(product, cache = TRUE)$status, "cached")
  changed <- product |>
    dl_add_transform(function(data) transform(data, id = id + 1L))
  expect_equal(dl_run(changed, stop_on_failure = FALSE)$status, "error")
  expect_equal(dl_read(lake, "orders")$id, 1L)
  unguarded <- dl_product("orders") |>
    dl_add_source(data.frame(id = 2L)) |>
    dl_add_target(lake)
  expect_equal(dl_run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_equal(dl_collect(first)$id, 1L)
})

test_that("readonly targets reject a workflow before calling its source", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- dl_open(file.path(root, "lake"))
  dl_close(lake)
  lake <- dl_open(file.path(root, "lake"), read_only = TRUE)
  withr::defer(dl_close(lake))
  calls <- 0
  product <- dl_product("orders") |>
    dl_add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    dl_add_target(lake)
  expect_snapshot(error = TRUE, dl_run(product))
  expect_equal(calls, 0)
})

test_that("ordinary R quality callbacks see the same values with native and lake execution", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  product <- dl_product("orders") |>
    dl_add_source(data.frame(id = 1:2, amount = c(10, -1))) |>
    dl_add_quality(function(data) all(data$amount >= 0), "positive")
  native <- dl_run(product, stop_on_failure = FALSE)
  stored <- dl_publish(
    product,
    to = file.path(root, "lake"),
    stop_on_failure = FALSE
  )
  expect_equal(native$status, "blocked")
  expect_equal(stored$status, "blocked")
  expect_equal(stored$quality, native$quality, ignore_attr = TRUE)
  lake <- dl_open(file.path(root, "lake"))
  withr::defer(dl_close(lake))
  expect_equal(nrow(dl_releases(lake)), 0L)
})
