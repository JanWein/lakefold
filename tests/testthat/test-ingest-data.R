test_that("frame ingestion retains types, gates input and caches identical deliveries", {
  f <- fixture()
  withr::defer(cleanup(f))
  contract <- f$contract
  contract$rules <- list()
  first <- dl_ingest_data(
    f$lake,
    f$good,
    contract,
    "risk.frame",
    code_version = "v1",
    input_contract = contract
  )
  second <- dl_ingest_data(
    f$lake,
    f$good,
    contract,
    "risk.frame",
    code_version = "v1",
    input_contract = contract
  )
  expect_equal(first$status, "published")
  expect_equal(second$status, "cached")
  expect_equal(second$release_id, first$release_id)
  expect_equal(dplyr::collect(dl_tbl(f$lake, "risk.frame"))$date, f$good$date)
  expect_equal(
    dir.exists(file.path(
      f$lake$config$landing,
      ".lakefold-staging",
      "risk.frame"
    )),
    FALSE
  )
  bad <- f$good
  bad$id[2] <- bad$id[1]
  result <- dl_ingest_data(
    f$lake,
    bad,
    contract,
    "risk.frame",
    code_version = "v1",
    input_contract = contract,
    stop_on_failure = FALSE
  )
  expect_equal(result$status, "blocked")
  expect_equal(unique(result$quality$stage), "ingest")
})
