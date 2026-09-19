test_that("convenience ingestion preserves publication and cache semantics", {
  f <- fixture()
  withr::defer(cleanup(f))
  source <- f$pipeline$steps$land
  first <- dl_ingest(
    f$lake,
    source,
    f$contract,
    "simple.orders",
    code_version = "v1"
  )
  second <- dl_ingest(
    f$lake,
    source,
    f$contract,
    "simple.orders",
    code_version = "v1"
  )
  expect_equal(first$status, "published")
  expect_equal(second$status, "cached")
  expect_equal(second$release_id, first$release_id)
})
