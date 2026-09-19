test_that("minimal and progressively composed workflows use ordinary R objects", {
  data <- data.frame(id = 1:2, amount = c(10, 20))
  simple <- dl_product("orders") |> dl_add_source(data)
  expect_equal(dl_collect(dl_run(simple)), tibble::as_tibble(data))
  product <- simple |>
    dl_add_transform(~ transform(.x, amount = amount * 2), "double") |>
    dl_add_contract(list(id = integer(), amount = double())) |>
    dl_add_quality(list(positive = ~ amount > 0, total = function(data) {
      sum(data$amount) == 60
    }))
  result <- dl_run(product)
  expect_equal(dl_collect(result)$amount, c(20, 40))
  expect_equal(result$status, "completed")
  expect_equal(dl_status(result)$success, TRUE)
  expect_equal(dl_inspect(product)$source$type, "data.frame")
  expect_equal(result$metadata$rows, 2L)
  expect_equal(result$metadata$schema, c(id = "integer", amount = "numeric"))
  expect_setequal(
    dl_quality(result)$rule,
    c(
      "schema",
      "types",
      "nonempty",
      "not_null:id",
      "not_null:amount",
      "positive",
      "total"
    )
  )
  expect_equal(tail(result$lifecycle$state, 1), "completed")
  expect_equal(result$inputs$rows, 2L)
  expect_equal(dl_collect(data), tibble::as_tibble(data))
})

test_that("definition, inspection and validation never call user functions", {
  calls <- 0
  product <- dl_product("orders") |>
    dl_add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    dl_add_transform(function(data) {
      calls <<- calls + 1
      data
    })
  expect_equal(
    dl_plan(product)$step,
    c("read", "transform", "validate", "publish")
  )
  expect_equal(attr(dl_plan(product), "complete"), TRUE)
  expect_equal(dl_inspect(dl_validate(product))$status, "validated")
  expect_equal(
    dl_inspect(dl_validate(product) |> dl_add_quality(~ id > 0))$status,
    "defined"
  )
  expect_equal(calls, 0)
  expect_equal(dl_run(product)$status, "completed")
  expect_equal(calls, 2)
  expect_snapshot({
    print(product)
    dl_explain(product)
  })
})

test_that("invalid specifications fail before acquisition", {
  expect_snapshot(error = TRUE, dl_validate(dl_product("orders")))
})

test_that("bad transformations preserve an actionable condition and run evidence", {
  product <- dl_product("orders") |>
    dl_add_source(data.frame(id = 1L)) |>
    dl_add_transform(function(data) list(id = 1L), "clean_orders")
  result <- dl_run(product, stop_on_failure = FALSE)
  expect_equal(result$status, "error")
  expect_match(
    conditionMessage(result$error),
    "clean_orders.*did not return a data frame"
  )
  expect_equal(tail(result$lifecycle$state, 1), "error")
  expect_snapshot(error = TRUE, dl_collect(result))
})

test_that("empty data and formula failures block a writer", {
  product <- dl_product("orders") |>
    dl_add_source(data.frame(amount = c(1, -1, NA))) |>
    dl_add_quality(~ amount >= 0)
  result <- dl_run(product, stop_on_failure = FALSE)
  expect_equal(result$status, "blocked")
  check <- result$quality[result$quality$rule == "quality_1", ]
  expect_equal(check$n_failed, 2)
  expect_equal(check$n_total, 3)
  expect_equal(
    dl_run(
      dl_product("empty") |> dl_add_source(data.frame(id = integer())),
      stop_on_failure = FALSE
    )$status,
    "blocked"
  )
})

test_that("contract prototypes, anonymous contracts and rule names normalize consistently", {
  contract <- dl_contract(
    columns = list(
      id = integer(),
      amount = double(),
      date = as.Date(character())
    )
  )
  product <- dl_product("orders") |> dl_add_contract(contract)
  expect_equal(product$contract$id, "orders.contract")
  expect_equal(
    unlist(contract$columns),
    c(id = "integer", amount = "numeric", date = "Date")
  )
  expect_snapshot(
    error = TRUE,
    dl_contract(columns = c(id = "integer", id = "numeric"))
  )
})

test_that("duplicate rule names across a contract and added checks fail preflight", {
  product <- dl_product("orders") |>
    dl_add_source(data.frame(id = 1L)) |>
    dl_add_contract(dl_contract(
      "orders",
      columns = c(id = "integer"),
      rules = list(dl_rule("positive", ~ id > 0))
    )) |>
    dl_add_quality(~ id >= 0, "positive")
  expect_snapshot(error = TRUE, dl_validate(product))
})

test_that("files normalize before execution and persist their original path", {
  root <- withr::local_tempdir()
  path <- file.path(root, "orders.csv")
  utils::write.csv(data.frame(id = 1:2), path, row.names = FALSE)
  product <- dl_product("orders") |> dl_add_source(path)
  expect_equal(product$source$path, normalizePath(path, winslash = "/"))
  expect_equal(dl_collect(dl_run(product))$id, 1:2)
  expect_equal(dl_inspect(product)$source$type, "file")
})

test_that("catalog delivery gets metadata without data rows or connections", {
  received <- NULL
  product <- dl_product("orders") |>
    dl_add_source(data.frame(
      id = 1:2,
      secret_value = c("private-a", "private-b")
    )) |>
    dl_add_catalog(function(metadata) received <<- metadata)
  result <- dl_run(product)
  expect_equal(received$rows, 2L)
  expect_equal(received$status, "completed")
  expect_equal(
    grepl("private-a", jsonlite::toJSON(received, auto_unbox = TRUE)),
    FALSE
  )
  expect_equal(result$warnings, character())
  product$catalogs <- list(function(metadata) stop("private credential"))
  expect_snapshot({
    result <- dl_run(product)
    print(result$status)
    print(result$warnings)
  })
  expect_equal(dl_collect(result)$id, 1:2)
})

test_that("execution warnings remain inspectable without entering metadata text", {
  detail <- "private source detail"
  product <- dl_product("orders") |>
    dl_add_source(function() {
      warning(detail)
      data.frame(id = 1L)
    })
  expect_snapshot({
    result <- dl_run(product)
    print(result$warnings)
  })
  expect_match(
    conditionMessage(result$warning_conditions[[1]]),
    "private source detail"
  )
  expect_equal(result$status, "completed")
  expect_equal(
    grepl(
      "private source detail",
      lakefold:::jencode(result$metadata),
      fixed = TRUE
    ),
    FALSE
  )
})
