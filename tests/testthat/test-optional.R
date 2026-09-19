test_that("real DuckLake preserves valid releases across failures and reconnects", {
  skip_if(
    Sys.getenv("DATALOOM_TEST_DUCKLAKE") != "true",
    "Set DATALOOM_TEST_DUCKLAKE=true for real extension tests"
  )
  f <- fixture("ducklake")
  on.exit(unlink(f$root, recursive = TRUE))
  first <- dl_run(f$pipeline, f$lake)
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  expect_equal(
    dl_run(f$pipeline, f$lake, stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_equal(dl_measure(f$lake, reserve_metric())$value, 300)
  config <- f$lake$config
  dl_disconnect(f$lake)
  lake <- dl_connect(config)
  on.exit(dl_disconnect(lake), add = TRUE)
  expect_equal(
    sum(
      dplyr::collect(dl_tbl(lake, "risk.validated", first$release_id))$reserve
    ),
    300
  )
})

test_that("pointblank runs actual checks including inactive/error steps", {
  skip_if_not_installed("pointblank")
  f <- fixture()
  on.exit(cleanup(f))
  contract <- f$contract
  contract$rules <- list(dl_pointblank("reserve", function(x) {
    pointblank::create_agent(x) |>
      pointblank::col_vals_gte(columns = "reserve", value = 0)
  }))
  expect_true(lakefold:::quality_ok(dl_validate(f$good, contract)))
  bad <- f$good
  bad$reserve[1] <- -1
  expect_false(lakefold:::quality_ok(dl_validate(bad, contract)))
  contract$rules <- list(dl_pointblank("inactive", function(x) {
    pointblank::create_agent(x) |>
      pointblank::col_vals_gte(columns = "reserve", value = 0, active = FALSE)
  }))
  expect_false(lakefold:::quality_ok(dl_validate(f$good, contract)))
})

test_that("dm adapter checks keys on pinned tables", {
  skip_if_not_installed("dm")
  f <- fixture()
  on.exit(cleanup(f))
  dl_run(f$pipeline, f$lake)
  model <- dl_model(
    f$lake,
    c(reserves = "risk.validated"),
    list(reserves = c("id", "date"))
  )
  expect_s3_class(model, "dm")
  expect_length(attr(model, "dl_releases"), 1)
})
