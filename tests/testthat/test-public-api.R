test_that("public functions use a package prefix without masking other grammars", {
  exports <- getNamespaceExports("dataraft")
  expect_length(exports[!startsWith(exports, "dr_")], 0L)
  expect_contains(exports, c("dr_product", "dr_recipe", "dr_workflow"))
})

test_that("collection preserves dplyr dispatch and ordinary result fields", {
  flow <- dr_workflow() |>
    dr_add_product(dr_product("orders")) |>
    dr_add_recipe(dr_recipe() |> dr_step_mutate(amount = amount * 2))
  result <- dr_trial(flow, data = data.frame(amount = c(10, 20)))
  expect_identical(result$status, "completed")
  expect_equal(dr_collect(result), dplyr::collect(result))
  expect_equal(dr_collect(result)$amount, c(20, 40))
  expect_identical(dr_extract_product(flow)$id, "orders")
})
