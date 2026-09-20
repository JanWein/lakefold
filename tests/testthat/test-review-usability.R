test_that("trial disables writers and catalogs throughout dependencies", {
  written <- 0L
  target <- function(data, context) {
    written <<- written + 1L
    list()
  }
  upstream <- product("input", data.frame(amount = c(10, 20))) |>
    set_target(target)
  product <- product(
    "orders",
    upstream,
    execution = execution_config(to = tempfile())
  ) |>
    add_quality(list(positive = ~ amount >= 0))
  before <- product
  result <- trial(product)
  expect_identical(written, 0L)
  expect_identical(product, before)
  expect_equal(collect(result)$amount, c(10, 20))
  definitions <- metric_set(
    "orders",
    total = sum(amount),
    count = dplyr::n(),
    approved = TRUE,
    code_version = "v1"
  )
  measured <- measure(result, metrics = definitions)
  expect_equal(collect(measured)$value, c(30, 2))
  expect_identical(all(quality(measured)$status == "passed"), TRUE)
  expect_match(status(measured)$message[1], "unpublished trial")
  expect_snapshot(
    error = TRUE,
    report_release(measured, "trial", code_version = "v1")
  )
})

test_that("quality rows identify predicate, required, duplicate and lookup failures", {
  rows <- data.frame(id = c(1L, 1L, 3L), amount = c(-10, 20, NA_real_))
  definition <- product("orders", rows) |>
    add_contract(contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    )) |>
    add_quality(list(positive = ~ amount >= 0))
  failed <- trial(definition, stop_on_failure = FALSE)
  expect_equal(quality_rows(failed, "positive")$id, c(1L, 3L))
  expect_equal(quality_rows(failed, "positive", limit = 1)$id, 1L)
  expect_equal(quality_rows(failed, "not_null:amount")$id, 3L)
  expect_equal(quality_rows(failed, "unique_key")$id, c(1L, 1L))
  lookup <- product("orders", data.frame(customer = c("a", "missing"))) |>
    add_lookup(data.frame(customer = "a"), by = "customer")
  failed <- trial(lookup, stop_on_failure = FALSE)
  expect_equal(quality_rows(failed, "lookup")$customer, "missing")
})

test_that("published result comparison uses exact releases and owns its connection", {
  root <- withr::local_tempdir()
  definition <- product("orders", data.frame(id = 1L, amount = 10)) |>
    add_contract(contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    ))
  first <- publish(definition, to = root)
  second <- publish(
    definition,
    data = data.frame(id = 1L, amount = 20),
    to = root
  )
  publish(definition, data = data.frame(id = 1L, amount = 99), to = root)
  difference <- compare(first, second)
  expect_equal(difference$numeric_summary$difference, 10)
  expect_identical(difference$from, first$release_id)
  expect_identical(difference$to, second$release_id)
  lake <- open_lake(root)
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
  close_lake(lake)
})

test_that("failed lake candidates support explicit row diagnosis after owned connection closes", {
  root <- withr::local_tempdir()
  definition <- product("orders", data.frame(amount = c(10, -2))) |>
    add_quality(list(positive = ~ amount >= 0))
  failed <- publish(definition, to = root, stop_on_failure = FALSE)
  expect_equal(quality_rows(failed, "positive")$amount, -2)
})


test_that("row diagnostics and comparisons borrow a live caller connection", {
  root <- withr::local_tempdir()
  lake <- open_lake(root)
  on.exit(close_lake(lake))
  definition <- product("orders", data.frame(id = 1L, amount = 10)) |>
    add_contract(contract(
      columns = c(id = "integer", amount = "numeric"),
      key = "id"
    )) |>
    add_quality(list(positive = ~ amount >= 0))
  first <- publish(definition, to = lake)
  second <- publish(
    definition,
    data = data.frame(id = 1L, amount = 20),
    to = lake
  )
  expect_equal(compare(first, second)$counts[["changed"]], 1)
  failed <- publish(
    definition,
    data = data.frame(id = 1L, amount = -2),
    to = lake,
    stop_on_failure = FALSE
  )
  expect_equal(quality_rows(failed, "positive")$amount, -2)
  expect_identical(DBI::dbIsValid(lake$con), TRUE)
})
