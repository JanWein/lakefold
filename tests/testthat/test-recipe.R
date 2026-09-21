test_that("recipes reuse deferred tidy expressions without changing definitions", {
  calls <- 0L
  threshold <- 10
  preparation <- tw_recipe() |>
    tw_step_mutate(amount = amount * 2) |>
    tw_step_filter(amount > !!threshold) |>
    tw_step_select(id, amount) |>
    tw_step_arrange(id)
  original <- preparation
  source <- function() {
    calls <<- calls + 1L
    data.frame(id = c(3L, 2L, 1L), amount = c(5, 20, 10), ignored = 0)
  }
  a <- tw_product("a", source) |> tw_add_recipe(preparation)
  b <- tw_product("b", data.frame(id = 4L, amount = 30)) |>
    tw_add_recipe(preparation)
  expect_identical(calls, 0L)
  expect_equal(
    tw_collect(tw_trial(a)),
    tibble::tibble(id = 1:2, amount = c(20, 40))
  )
  expect_equal(tw_collect(tw_trial(b))$amount, 60)
  expect_identical(calls, 1L)
  expect_identical(preparation, original)
})

test_that("summaries, selection and custom transformations retain ordinary semantics", {
  preparation <- tw_recipe() |>
    tw_step_distinct(group, amount, .keep_all = TRUE) |>
    tw_step_rename(value = amount) |>
    tw_step_summarise(total = sum(value), .by = group) |>
    tw_step_transform(~ dplyr::mutate(.x, total = total + 1))
  data <- data.frame(group = c("a", "a", "a", "b"), amount = c(1, 1, 2, 4))
  out <- tw_product("summary", data) |>
    tw_add_recipe(preparation) |>
    tw_trial() |>
    tw_collect()
  expect_equal(out, tibble::tibble(group = c("a", "b"), total = c(4, 5)))
})

test_that("recipe lookups remain replaceable shared execution dependencies", {
  calls <- 0L
  customers <- tw_product("customers", function() {
    calls <<- calls + 1L
    data.frame(id = 1:2, region = c("North", "South"))
  })
  preparation <- tw_recipe() |> tw_step_lookup(customers, by = "id")
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders")) |>
    tw_add_recipe(preparation) |>
    tw_add_source(data.frame(id = 1:2), name = "orders")
  expect_identical(calls, 0L)
  expect_equal(tw_collect(tw_trial(flow))$region, c("North", "South"))
  expect_identical(calls, 1L)
  corrected <- tw_trial(
    flow,
    sources = list(customers = data.frame(id = 1:2, region = c("East", "West")))
  )
  expect_equal(tw_collect(corrected)$region, c("East", "West"))
  expect_identical(calls, 1L)
})

test_that("recipes preserve lazy SQL until collect", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "orders", data.frame(id = 1:3, amount = c(1, 2, 3)))
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders")) |>
    tw_add_source(tw_source_database(con, table = "orders")) |>
    tw_add_recipe(
      tw_recipe() |>
        tw_step_filter(id > 1) |>
        tw_step_mutate(amount = amount * 2)
    )
  result <- tw_trial(flow)
  expect_s3_class(result$data, "tbl_sql")
  expect_equal(tw_collect(result)$amount, c(4, 6))
  expect_identical(DBI::dbIsValid(con), TRUE)
})
