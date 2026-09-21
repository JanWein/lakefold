test_that("trial disables writers and catalogs throughout dependencies", {
  written <- 0L
  target <- function(data, context) {
    written <<- written + 1L
    list()
  }
  upstream <- tw_product("input", data.frame(amount = c(10, 20))) |>
    tw_set_target(target)
  product <- tw_product(
    "orders",
    upstream,
    execution = tw_execution_config(to = tempfile())
  ) |>
    tw_add_quality(list(positive = ~ amount >= 0))
  before <- product
  result <- tw_trial(product)
  expect_identical(written, 0L)
  expect_identical(product, before)
  expect_equal(tw_collect(result)$amount, c(10, 20))
  definitions <- tw_metric_set(
    "orders",
    total = sum(amount),
    count = dplyr::n(),
    approved = TRUE,
    code_version = "v1"
  )
  measured <- tw_measure(result, metrics = definitions)
  expect_equal(tw_collect(measured)$value, c(30, 2))
  expect_identical(all(tw_quality(measured)$status == "passed"), TRUE)
  expect_match(tw_status(measured)$message[1], "unpublished trial")
  expect_snapshot(
    error = TRUE,
    tw_report_release(measured, "trial", code_version = "v1")
  )
})

test_that("quality rows identify predicate, required, duplicate and lookup failures", {
  rows <- data.frame(id = c(1L, 1L, 3L), amount = c(-10, 20, NA_real_))
  definition <- tw_product("orders", rows) |>
    tw_add_contract(tw_contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    )) |>
    tw_add_quality(list(positive = ~ amount >= 0))
  failed <- tw_trial(definition, stop_on_failure = FALSE)
  expect_equal(tw_quality_rows(failed, "positive")$id, c(1L, 3L))
  expect_equal(tw_quality_rows(failed, "positive", limit = 1)$id, 1L)
  expect_equal(tw_quality_rows(failed, "not_null:amount")$id, 3L)
  expect_equal(tw_quality_rows(failed, "unique_key")$id, c(1L, 1L))
  lookup <- tw_product("orders", data.frame(customer = c("a", "missing"))) |>
    tw_add_lookup(data.frame(customer = "a"), by = "customer")
  failed <- tw_trial(lookup, stop_on_failure = FALSE)
  expect_equal(tw_quality_rows(failed, "lookup")$customer, "missing")
})

test_that("published result comparison uses exact releases and owns its connection", {
  root <- withr::local_tempdir()
  definition <- tw_product("orders", data.frame(id = 1L, amount = 10)) |>
    tw_add_contract(tw_contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    ))
  first <- tw_publish(definition, to = root)
  second <- tw_publish(
    definition,
    data = data.frame(id = 1L, amount = 20),
    to = root
  )
  tw_publish(definition, data = data.frame(id = 1L, amount = 99), to = root)
  difference <- tw_compare(first, second)
  expect_equal(difference$numeric_summary$difference, 10)
  expect_identical(difference$from, first$release_id)
  expect_identical(difference$to, second$release_id)
  lake <- tw_open_lake(root)
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
  tw_close_lake(lake)
})

test_that("failed lake candidates support explicit row diagnosis after owned connection closes", {
  root <- withr::local_tempdir()
  definition <- tw_product("orders", data.frame(amount = c(10, -2))) |>
    tw_add_quality(list(positive = ~ amount >= 0))
  failed <- tw_publish(definition, to = root, stop_on_failure = FALSE)
  expect_equal(tw_quality_rows(failed, "positive")$amount, -2)
})


test_that("row diagnostics and comparisons borrow a live caller connection", {
  root <- withr::local_tempdir()
  lake <- tw_open_lake(root)
  on.exit(tw_close_lake(lake))
  definition <- tw_product("orders", data.frame(id = 1L, amount = 10)) |>
    tw_add_contract(tw_contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    )) |>
    tw_add_quality(list(positive = ~ amount >= 0))
  first <- tw_publish(definition, to = lake)
  second <- tw_publish(
    definition,
    data = data.frame(id = 1L, amount = 20),
    to = lake
  )
  expect_equal(tw_compare(first, second)$counts[["changed"]], 1)
  failed <- tw_publish(
    definition,
    data = data.frame(id = 1L, amount = -2),
    to = lake,
    stop_on_failure = FALSE
  )
  expect_equal(tw_quality_rows(failed, "positive")$amount, -2)
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
})
