test_that("native and lake targets run the same transformations and quality rules", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(
    file.path(root, "lake"),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(tw_close_lake(lake))
  received <- NULL
  product <- tw_product("orders") |>
    tw_add_source(data.frame(id = 1:2, amount = c(10, 20))) |>
    tw_add_transform(
      function(data) transform(data, amount = amount * 2),
      "double"
    ) |>
    tw_add_contract(c(id = "integer", amount = "numeric")) |>
    tw_add_quality(~ amount > 0) |>
    tw_add_catalog(function(metadata) received <<- metadata)
  native <- tw_run(product)
  persisted <- tw_run(product |> tw_set_target(lake))
  expect_equal(tw_collect(native), tw_collect(persisted))
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
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  make <- function(data) {
    tw_product("orders") |>
      tw_add_source(data) |>
      tw_add_transform(function(data) data.frame(total = sum(data$amount))) |>
      tw_add_quality(~ total >= 0) |>
      tw_set_target(lake)
  }
  first <- tw_run(make(data.frame(amount = c(10, 20))))
  expect_equal(tw_collect(first)$total, 30)
  second <- tw_run(make(data.frame(amount = c(20, 20))))
  expect_equal(tw_collect(second)$total, 40)
  blocked <- tw_run(make(data.frame(amount = -10)), stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(tw_read_release(lake, "orders")$total, 40)
  expect_equal(tw_collect(first)$total, 30)
  unguarded <- tw_product("orders") |>
    tw_add_source(data.frame(total = 50)) |>
    tw_set_target(lake)
  expect_equal(tw_run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_snapshot(
    error = TRUE,
    tw_write_data(lake, data.frame(total = 50), "orders")
  )
})

test_that("file publication archives original bytes and records transform definitions", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  path <- file.path(root, "orders.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  product <- tw_product("orders") |>
    tw_add_source(path) |>
    tw_add_transform(
      function(data) transform(data, amount = id * 10),
      "add_amount"
    )
  result <- tw_publish(product, to = file.path(root, "lake"))
  expect_equal(tw_collect(result)$amount, c(10, 20))
  expect_identical(
    readBin(result$inputs$landed_path, "raw", n = file.info(path)$size),
    readBin(path, "raw", n = file.info(path)$size)
  )
  lake <- tw_open_lake(file.path(root, "lake"), read_only = TRUE)
  withr::defer(tw_close_lake(lake))
  definitions <- tw_registry(lake, "assets")
  expect_equal(
    any(grepl("add_amount", definitions$definition, fixed = TRUE)),
    TRUE
  )
})

test_that("partition targets validate retained partitions and preserve published history", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(
    file.path(root, "lake"),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(tw_close_lake(lake))
  contract <- tw_contract(
    "orders",
    columns = c(id = "integer", month = "character", amount = "numeric"),
    key = c("id", "month")
  )
  make <- function(month, amount) {
    tw_product("orders") |>
      tw_add_source(data.frame(id = 1L, month = month, amount = amount)) |>
      tw_add_contract(contract) |>
      tw_add_quality(~ amount >= 0) |>
      tw_set_target(tw_target_lake(lake, partition_by = "month"))
  }
  first <- tw_run(make("August", 10))
  second <- tw_run(make("September", 20))
  expect_equal(nrow(tw_collect(second)), 2L)
  expect_equal(sum(tw_collect(second)$amount), 30)
  expect_equal(
    tw_run(make("August", -1), stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_equal(sum(tw_read_release(lake, "orders")$amount), 30)
  expect_equal(nrow(tw_collect(first)), 1L)
})

test_that("explicit contracts and versioned definitions cannot be silently weakened", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  product <- tw_product("orders", version = "1", code_version = "v1") |>
    tw_add_source(data.frame(id = 1L)) |>
    tw_add_contract(c(id = "integer")) |>
    tw_set_target(lake)
  first <- tw_run(product)
  cached <- tw_run(product, cache = TRUE)
  expect_identical(cached$status, "cached")
  expect_false(identical(cached$run_id, first$run_id))
  expect_identical(cached$release_id, first$release_id)
  expect_gt(nrow(cached$quality), 0L)
  expect_setequal(cached$quality$run_id, first$run_id)
  expect_setequal(cached$metadata$quality$run_id, first$run_id)
  changed <- product |>
    tw_add_transform(function(data) transform(data, id = id + 1L))
  expect_equal(tw_run(changed, stop_on_failure = FALSE)$status, "error")
  expect_equal(tw_read_release(lake, "orders")$id, 1L)
  unguarded <- tw_product("orders") |>
    tw_add_source(data.frame(id = 2L)) |>
    tw_set_target(lake)
  expect_equal(tw_run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_equal(tw_collect(first)$id, 1L)
})

test_that("readonly targets reject a workflow before calling its source", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  tw_close_lake(lake)
  lake <- tw_open_lake(file.path(root, "lake"), read_only = TRUE)
  withr::defer(tw_close_lake(lake))
  calls <- 0
  product <- tw_product("orders") |>
    tw_add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    tw_set_target(lake)
  expect_snapshot(error = TRUE, tw_run(product))
  expect_equal(calls, 0)
})

test_that("ordinary R quality callbacks see the same values with native and lake execution", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  product <- tw_product("orders") |>
    tw_add_source(data.frame(id = 1:2, amount = c(10, -1))) |>
    tw_add_quality(function(data) all(data$amount >= 0), "positive")
  native <- tw_run(product, stop_on_failure = FALSE)
  stored <- tw_publish(
    product,
    to = file.path(root, "lake"),
    stop_on_failure = FALSE
  )
  expect_equal(native$status, "blocked")
  expect_equal(stored$status, "blocked")
  expect_equal(stored$quality, native$quality, ignore_attr = TRUE)
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  expect_equal(nrow(tw_releases(lake)), 0L)
})

test_that("lake preparation failures have one durable run and archived provenance", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  a <- file.path(root, "a.csv")
  b <- file.path(root, "b.csv")
  utils::write.csv(data.frame(id = 1L), a, row.names = FALSE)
  utils::write.csv(data.frame(id = 2L), b, row.names = FALSE)
  calls <- 0L
  broken_reader <- function(path) {
    calls <<- calls + 1L
    stop("Cannot decode input")
  }
  definition <- tw_product("joined") |>
    tw_add_source(a, "a") |>
    tw_add_source(b, "b", reader = broken_reader) |>
    tw_add_transform(function(data) rbind(data$a, data$b)) |>
    tw_set_target(lake)
  failed <- tw_run(definition, stop_on_failure = FALSE)
  runs <- tw_registry(lake, "runs")
  expect_equal(nrow(runs), 1L)
  expect_identical(runs$run_id, failed$run_id)
  expect_identical(runs$status, "error")
  expect_equal(calls, 1L)
  expect_equal(nrow(failed$inputs), 2L)
  expect_true(all(file.exists(failed$inputs$landed_path)))
  expect_equal(nrow(tw_releases(lake)), 0L)

  joined <- definition |>
    tw_add_source(b, "b", replace = TRUE) |>
    tw_add_transform(function(data) stop("Combining failed"), "fail")
  failed_join <- tw_run(joined, stop_on_failure = FALSE)
  expect_identical(failed_join$status, "error")
  expect_equal(nrow(tw_registry(lake, "runs")), 2L)
  expect_equal(nrow(failed_join$inputs), 2L)

  success <- definition |> tw_add_source(b, "b", replace = TRUE) |> tw_run()
  expect_identical(success$status, "published")
  expect_equal(nrow(tw_registry(lake, "runs")), 3L)
  expect_equal(nrow(success$inputs), 3L)
  expect_equal(tw_collect(success)$id, 1:2)
  expect_false(any(tw_registry(lake, "runs")$status == "running"))
})

test_that("automatic definitions include publication policy while explicit versions stay immutable", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  schema <- tw_contract(
    columns = c(id = "integer", month = "character"),
    key = "id"
  )
  definition <- tw_product("orders", contract = schema) |>
    tw_add_source(data.frame(id = 1L, month = "August")) |>
    tw_set_target(lake)
  first <- tw_run(definition)
  partitioned <- definition |>
    tw_add_source(
      data.frame(id = 2L, month = "September"),
      "source_1",
      replace = TRUE
    ) |>
    tw_set_target(tw_target_lake(lake, partition_by = "month"))
  second <- tw_run(partitioned)
  expect_identical(second$status, "published")
  expect_equal(tw_collect(second)$id, 1:2)
  expect_equal(tw_collect(first)$id, 1L)
  expect_equal(nrow(tw_registry(lake, "runs")), 2L)
  fixed <- tw_product("fixed", contract = schema, version = "1") |>
    tw_add_source(data.frame(id = 1L, month = "August")) |>
    tw_set_target(lake)
  tw_run(fixed)
  changed <- fixed |>
    tw_set_target(tw_target_lake(lake, partition_by = "month"))
  rejected <- tw_run(changed, stop_on_failure = FALSE)
  expect_identical(rejected$status, "error")
  expect_match(conditionMessage(rejected$error), "version bump")
  expect_equal(tw_read_release(lake, "fixed")$id, 1L)
})
