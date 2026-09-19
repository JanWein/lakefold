test_that("dbt releases preserve snapshots and revalidate mutable source relations", {
  f <- fixture()
  withr::defer(cleanup(f))
  DBI::dbExecute(f$lake$con, "CREATE SCHEMA lake.marts")
  DBI::dbExecute(
    f$lake$con,
    "CREATE TABLE lake.marts.customer_revenue AS SELECT 101 AS customer_id, 100.0::DOUBLE AS revenue"
  )
  parsed <- lakefold:::dbt_read_artifacts(system.file(
    "extdata",
    "dbt-artifacts",
    package = "lakefold"
  ))
  result <- structure(
    list(
      success = TRUE,
      status = 0L,
      command = "build",
      results = parsed$results,
      manifest = parsed$manifest
    ),
    class = "dl_dbt_result"
  )
  contract <- dl_contract(
    "revenue",
    "1",
    "Analytics",
    "Customer revenue",
    "One customer",
    c(customer_id = "integer", revenue = "numeric"),
    key = "customer_id",
    rules = list(dl_rule("positive", function(data) {
      counts <- dplyr::collect(dplyr::summarise(data, n = sum(revenue < 0)))
      counts$n == 0
    }))
  )
  first <- dl_dbt_publish(
    f$lake,
    result,
    "model.shop.customer_revenue",
    contract,
    "shop.revenue",
    code_version = "v1"
  )
  expect_equal(first$status, "published")
  DBI::dbExecute(
    f$lake$con,
    "UPDATE lake.marts.customer_revenue SET revenue = -10"
  )
  second <- dl_dbt_publish(
    f$lake,
    result,
    "model.shop.customer_revenue",
    contract,
    "shop.revenue",
    code_version = "v1",
    stop_on_failure = FALSE
  )
  expect_equal(second$status, "blocked")
  expect_equal(dplyr::collect(dl_tbl(f$lake, "shop.revenue"))$revenue, 100)
  expect_equal(dl_releases(f$lake, "shop.revenue")$release_id, first$release_id)
  expect_setequal(dl_quality(first)$stage, c("model", "candidate"))
  edges <- dl_lineage(f$lake, "shop.revenue")
  expect_equal(edges$from_id, "model.shop.customer_revenue")
  expect_equal(edges$from_version, parsed$manifest$metadata$invocation_id)
  result$command <- "test"
  expect_snapshot(
    error = TRUE,
    dl_dbt_publish(
      f$lake,
      result,
      "model.shop.customer_revenue",
      contract,
      "shop.revenue",
      code_version = "v1"
    )
  )
})
