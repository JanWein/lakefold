test_that("native and lake targets run the same transformations and quality rules", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(
    file.path(root, "lake"),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(close_lake(lake))
  received <- NULL
  product <- product("orders") |>
    add_source(data.frame(id = 1:2, amount = c(10, 20))) |>
    add_transform(
      function(data) transform(data, amount = amount * 2),
      "double"
    ) |>
    add_contract(c(id = "integer", amount = "numeric")) |>
    add_quality(~ amount > 0) |>
    add_catalog(function(metadata) received <<- metadata)
  native <- run(product)
  persisted <- run(product |> set_target(lake))
  expect_equal(collect(native), collect(persisted))
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
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  make <- function(data) {
    product("orders") |>
      add_source(data) |>
      add_transform(function(data) data.frame(total = sum(data$amount))) |>
      add_quality(~ total >= 0) |>
      set_target(lake)
  }
  first <- run(make(data.frame(amount = c(10, 20))))
  expect_equal(collect(first)$total, 30)
  second <- run(make(data.frame(amount = c(20, 20))))
  expect_equal(collect(second)$total, 40)
  blocked <- run(make(data.frame(amount = -10)), stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(read_release(lake, "orders")$total, 40)
  expect_equal(collect(first)$total, 30)
  unguarded <- product("orders") |>
    add_source(data.frame(total = 50)) |>
    set_target(lake)
  expect_equal(run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_snapshot(
    error = TRUE,
    write_data(lake, data.frame(total = 50), "orders")
  )
})

test_that("file publication archives original bytes and records transform definitions", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  path <- file.path(root, "orders.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  product <- product("orders") |>
    add_source(path) |>
    add_transform(
      function(data) transform(data, amount = id * 10),
      "add_amount"
    )
  result <- publish(product, to = file.path(root, "lake"))
  expect_equal(collect(result)$amount, c(10, 20))
  expect_identical(
    readBin(result$inputs$landed_path, "raw", n = file.info(path)$size),
    readBin(path, "raw", n = file.info(path)$size)
  )
  lake <- open_lake(file.path(root, "lake"), read_only = TRUE)
  withr::defer(close_lake(lake))
  definitions <- registry(lake, "assets")
  expect_equal(
    any(grepl("add_amount", definitions$definition, fixed = TRUE)),
    TRUE
  )
})

test_that("partition targets validate retained partitions and preserve published history", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(
    file.path(root, "lake"),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(close_lake(lake))
  contract <- contract(
    "orders",
    columns = c(id = "integer", month = "character", amount = "numeric"),
    key = c("id", "month")
  )
  make <- function(month, amount) {
    product("orders") |>
      add_source(data.frame(id = 1L, month = month, amount = amount)) |>
      add_contract(contract) |>
      add_quality(~ amount >= 0) |>
      set_target(target_lake(lake, partition_by = "month"))
  }
  first <- run(make("August", 10))
  second <- run(make("September", 20))
  expect_equal(nrow(collect(second)), 2L)
  expect_equal(sum(collect(second)$amount), 30)
  expect_equal(
    run(make("August", -1), stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_equal(sum(read_release(lake, "orders")$amount), 30)
  expect_equal(nrow(collect(first)), 1L)
})

test_that("explicit contracts and versioned definitions cannot be silently weakened", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  product <- product("orders", version = "1", code_version = "v1") |>
    add_source(data.frame(id = 1L)) |>
    add_contract(c(id = "integer")) |>
    set_target(lake)
  first <- run(product)
  cached <- run(product, cache = TRUE)
  expect_identical(cached$status, "cached")
  expect_false(identical(cached$run_id, first$run_id))
  expect_identical(cached$release_id, first$release_id)
  expect_gt(nrow(cached$quality), 0L)
  expect_setequal(cached$quality$run_id, first$run_id)
  expect_setequal(cached$metadata$quality$run_id, first$run_id)
  changed <- product |>
    add_transform(function(data) transform(data, id = id + 1L))
  expect_equal(run(changed, stop_on_failure = FALSE)$status, "error")
  expect_equal(read_release(lake, "orders")$id, 1L)
  unguarded <- product("orders") |>
    add_source(data.frame(id = 2L)) |>
    set_target(lake)
  expect_equal(run(unguarded, stop_on_failure = FALSE)$status, "error")
  expect_equal(collect(first)$id, 1L)
})

test_that("readonly targets reject a workflow before calling its source", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  close_lake(lake)
  lake <- open_lake(file.path(root, "lake"), read_only = TRUE)
  withr::defer(close_lake(lake))
  calls <- 0
  product <- product("orders") |>
    add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    set_target(lake)
  expect_snapshot(error = TRUE, run(product))
  expect_equal(calls, 0)
})

test_that("ordinary R quality callbacks see the same values with native and lake execution", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  product <- product("orders") |>
    add_source(data.frame(id = 1:2, amount = c(10, -1))) |>
    add_quality(function(data) all(data$amount >= 0), "positive")
  native <- run(product, stop_on_failure = FALSE)
  stored <- publish(
    product,
    to = file.path(root, "lake"),
    stop_on_failure = FALSE
  )
  expect_equal(native$status, "blocked")
  expect_equal(stored$status, "blocked")
  expect_equal(stored$quality, native$quality, ignore_attr = TRUE)
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  expect_equal(nrow(releases(lake)), 0L)
})

test_that("lake preparation failures have one durable run and archived provenance", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  a <- file.path(root, "a.csv")
  b <- file.path(root, "b.csv")
  utils::write.csv(data.frame(id = 1L), a, row.names = FALSE)
  utils::write.csv(data.frame(id = 2L), b, row.names = FALSE)
  calls <- 0L
  broken_reader <- function(path) {
    calls <<- calls + 1L
    stop("Cannot decode input")
  }
  definition <- product("joined") |>
    add_source(a, "a") |>
    add_source(b, "b", reader = broken_reader) |>
    add_transform(function(data) rbind(data$a, data$b)) |>
    set_target(lake)
  failed <- run(definition, stop_on_failure = FALSE)
  runs <- registry(lake, "runs")
  expect_equal(nrow(runs), 1L)
  expect_identical(runs$run_id, failed$run_id)
  expect_identical(runs$status, "error")
  expect_equal(calls, 1L)
  expect_equal(nrow(failed$inputs), 2L)
  expect_true(all(file.exists(failed$inputs$landed_path)))
  expect_equal(nrow(releases(lake)), 0L)

  joined <- definition |>
    add_source(b, "b", replace = TRUE) |>
    add_transform(function(data) stop("Combining failed"), "fail")
  failed_join <- run(joined, stop_on_failure = FALSE)
  expect_identical(failed_join$status, "error")
  expect_equal(nrow(registry(lake, "runs")), 2L)
  expect_equal(nrow(failed_join$inputs), 2L)

  success <- definition |> add_source(b, "b", replace = TRUE) |> run()
  expect_identical(success$status, "published")
  expect_equal(nrow(registry(lake, "runs")), 3L)
  expect_equal(nrow(success$inputs), 3L)
  expect_equal(collect(success)$id, 1:2)
  expect_false(any(registry(lake, "runs")$status == "running"))
})

test_that("automatic definitions include publication policy while explicit versions stay immutable", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  schema <- contract(
    columns = c(id = "integer", month = "character"),
    key = "id"
  )
  definition <- product("orders", contract = schema) |>
    add_source(data.frame(id = 1L, month = "August")) |>
    set_target(lake)
  first <- run(definition)
  partitioned <- definition |>
    add_source(
      data.frame(id = 2L, month = "September"),
      "source_1",
      replace = TRUE
    ) |>
    set_target(target_lake(lake, partition_by = "month"))
  second <- run(partitioned)
  expect_identical(second$status, "published")
  expect_equal(collect(second)$id, 1:2)
  expect_equal(collect(first)$id, 1L)
  expect_equal(nrow(registry(lake, "runs")), 2L)
  fixed <- product("fixed", contract = schema, version = "1") |>
    add_source(data.frame(id = 1L, month = "August")) |>
    set_target(lake)
  run(fixed)
  changed <- fixed |> set_target(target_lake(lake, partition_by = "month"))
  rejected <- run(changed, stop_on_failure = FALSE)
  expect_identical(rejected$status, "error")
  expect_match(conditionMessage(rejected$error), "version bump")
  expect_equal(read_release(lake, "fixed")$id, 1L)
})
