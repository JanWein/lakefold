test_that("write results are pinned product and lookup inputs", {
  skip_if_not_installed("duckdb")
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  connections <- 0L
  connect <- connect_lake
  local_mocked_bindings(connect_lake = function(...) {
    connections <<- connections + 1L
    connect(...)
  })
  orders <- data.frame(id = 1:2, amount = c(10, 20))
  written <- tw_write_data(lake, orders, "orders")
  reference <- tw_write_data(
    lake,
    data.frame(id = 1:2, label = c("North", "South")),
    "customers"
  )
  release <- resolve_release(lake, "orders", written$release_id)
  expect_identical(written$asset, "orders")
  expect_identical(written$output_config, lake$config)
  expect_identical(written$output_lake, lake)
  expect_identical(
    written$outputs,
    list(
      type = "lake release",
      database = "lake",
      schema = release$schema_name[[1]],
      table = release$table_name[[1]],
      asset = "orders",
      release_id = written$release_id
    )
  )
  definition <- tw_product("enriched", written) |>
    tw_add_lookup(reference, by = "id")
  result <- tw_run(definition)
  expect_identical(result$inputs$release_id[[1]], written$release_id)
  expect_identical(result$inputs$asset[[1]], written$asset)
  expect_equal(
    tw_collect(result),
    tibble::as_tibble(transform(orders, label = c("North", "South"))),
    ignore_attr = TRUE
  )
  expect_true(DBI::dbIsValid(lake$con))
  expect_identical(connections, 0L)
  tw_close_lake(lake)
  expect_equal(tw_collect(written), tibble::as_tibble(orders))
  expect_equal(
    definition |> tw_run() |> tw_collect(),
    tibble::as_tibble(transform(orders, label = c("North", "South"))),
    ignore_attr = TRUE
  )
  expect_false(DBI::dbIsValid(lake$con))
  expect_gt(connections, 0L)
})

test_that("owned file and function writes retain recoverable cached references", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  config <- tw_lake_config(path = file.path(root, "lake"))
  orders <- data.frame(id = 1:2, amount = c(10, 20))
  path <- file.path(root, "orders.csv")
  utils::write.csv(orders, path, row.names = FALSE)
  for (input in list(path, function() orders, orders)) {
    first <- tw_write_data(config, input, "orders")
    cached <- tw_write_data(config, input, "orders")
    expect_identical(cached$status, "cached")
    expect_identical(cached$release_id, first$release_id)
    expect_identical(cached$outputs, first$outputs)
    for (result in list(first, cached)) {
      expect_null(result$output_lake)
      expect_s3_class(result$output_config, "tw_config")
      expect_identical(result$asset, "orders")
      expect_equal(tw_collect(result), tibble::as_tibble(orders))
      expect_equal(
        tw_product("copy", result) |> tw_run() |> tw_collect(),
        tibble::as_tibble(orders),
        ignore_attr = TRUE
      )
    }
  }
})

test_that("write result measures retain old release identity and reject failures", {
  skip_if_not_installed("duckdb")
  config <- tw_lake_config(path = file.path(withr::local_tempdir(), "lake"))
  first <- tw_write_data(config, data.frame(amount = 10), "orders")
  later <- tw_write_data(config, data.frame(amount = 40), "orders")
  total <- tw_metric(
    "orders.total",
    "orders",
    expr = sum(amount),
    approved = TRUE,
    code_version = "metric-v1"
  )
  measurement <- tw_measure(first, total)
  expect_equal(measurement$value, 10)
  expect_identical(
    attr(measurement, "tw_manifest")$release_id,
    first$release_id
  )
  expect_equal(tw_measure(later, total)$value, 40)
  expect_equal(
    tw_product("copy", first) |> tw_run() |> tw_collect(),
    tibble::tibble(amount = 10),
    ignore_attr = TRUE
  )
  blocked <- tw_write_data(
    config,
    data.frame(amount = "invalid"),
    "orders",
    stop_on_failure = FALSE
  )
  expect_identical(blocked$status, "blocked")
  expect_null(blocked$output_config)
  expect_null(blocked$output_lake)
  expect_error(tw_product("blocked", blocked), "successful")
  expect_error(tw_measure(blocked, total), "successful published result")
})
