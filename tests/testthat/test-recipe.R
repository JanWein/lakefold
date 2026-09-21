test_that("recipes reuse deferred tidy expressions without changing definitions", {
  calls <- 0L
  threshold <- 10
  preparation <- recipe() |>
    step_mutate(amount = amount * 2) |>
    step_filter(amount > !!threshold) |>
    step_select(id, amount) |>
    step_arrange(id)
  original <- preparation
  source <- function() {
    calls <<- calls + 1L
    data.frame(id = c(3L, 2L, 1L), amount = c(5, 20, 10), ignored = 0)
  }
  a <- product("a", source) |> add_recipe(preparation)
  b <- product("b", data.frame(id = 4L, amount = 30)) |> add_recipe(preparation)
  expect_identical(calls, 0L)
  expect_equal(collect(trial(a)), tibble::tibble(id = 1:2, amount = c(20, 40)))
  expect_equal(collect(trial(b))$amount, 60)
  expect_identical(calls, 1L)
  expect_identical(preparation, original)
})

test_that("summaries, selection and custom transformations retain ordinary semantics", {
  preparation <- recipe() |>
    step_distinct(group, amount, .keep_all = TRUE) |>
    step_rename(value = amount) |>
    step_summarise(total = sum(value), .by = group) |>
    step_transform(~ dplyr::mutate(.x, total = total + 1))
  data <- data.frame(group = c("a", "a", "a", "b"), amount = c(1, 1, 2, 4))
  out <- product("summary", data) |>
    add_recipe(preparation) |>
    trial() |>
    collect()
  expect_equal(out, tibble::tibble(group = c("a", "b"), total = c(4, 5)))
})

test_that("recipe lookups remain replaceable shared execution dependencies", {
  calls <- 0L
  customers <- product("customers", function() {
    calls <<- calls + 1L
    data.frame(id = 1:2, region = c("North", "South"))
  })
  preparation <- recipe() |> step_lookup(customers, by = "id")
  flow <- workflow() |>
    add_product(product("orders")) |>
    add_recipe(preparation) |>
    add_source(data.frame(id = 1:2), name = "orders")
  expect_identical(calls, 0L)
  expect_equal(collect(trial(flow))$region, c("North", "South"))
  expect_identical(calls, 1L)
  corrected <- trial(
    flow,
    sources = list(customers = data.frame(id = 1:2, region = c("East", "West")))
  )
  expect_equal(collect(corrected)$region, c("East", "West"))
  expect_identical(calls, 1L)
})

test_that("recipes preserve lazy SQL until collect", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "orders", data.frame(id = 1:3, amount = c(1, 2, 3)))
  flow <- workflow() |>
    add_product(product("orders")) |>
    add_source(source_database(con, table = "orders")) |>
    add_recipe(
      recipe() |> step_filter(id > 1) |> step_mutate(amount = amount * 2)
    )
  result <- trial(flow)
  expect_s3_class(result$data, "tbl_sql")
  expect_equal(collect(result)$amount, c(4, 6))
  expect_identical(DBI::dbIsValid(con), TRUE)
})
