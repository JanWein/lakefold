test_that("public functions use a package prefix without masking other grammars", {
  exports <- getNamespaceExports("tidyweave")
  expect_length(exports[!startsWith(exports, "tw_")], 0L)
  expect_contains(exports, c("tw_product", "tw_recipe", "tw_workflow"))
})

test_that("collection preserves dplyr dispatch and ordinary result fields", {
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders")) |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2))
  result <- tw_trial(flow, data = data.frame(amount = c(10, 20)))
  expect_identical(result$status, "completed")
  expect_equal(tw_collect(result), dplyr::collect(result))
  expect_equal(tw_collect(result)$amount, c(20, 40))
  expect_identical(tw_extract_product(flow)$id, "orders")
})
