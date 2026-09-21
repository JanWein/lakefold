test_that("the filter method registers with dplyr without masking stats", {
  method <- utils::getS3method(
    "filter",
    "tw_product",
    envir = asNamespace("dplyr")
  )
  expect_identical(environment(method), asNamespace("tidyweave"))
  filtered <- tw_product("orders", data.frame(amount = c(10, 20))) |>
    dplyr::filter(amount > 10) |>
    tw_trial()
  expect_equal(tw_collect(filtered)$amount, 20)
  expect_identical("filter" %in% getNamespaceExports("tidyweave"), FALSE)
})
