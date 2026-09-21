test_that("the filter method registers with dplyr without masking stats", {
  method <- utils::getS3method(
    "filter",
    "dr_product",
    envir = asNamespace("dplyr")
  )
  expect_identical(environment(method), asNamespace("dataraft.core"))
  filtered <- dr_product("orders", data.frame(amount = c(10, 20))) |>
    dplyr::filter(amount > 10) |>
    dr_trial()
  expect_equal(dr_collect(filtered)$amount, 20)
  expect_identical("filter" %in% getNamespaceExports("dataraft"), FALSE)
})
