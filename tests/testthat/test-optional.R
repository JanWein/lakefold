test_that("real DuckLake preserves valid releases across failures and reconnects", {
  skip_if(
    Sys.getenv("TIDYWEAVE_TEST_DUCKLAKE") != "true",
    "Set TIDYWEAVE_TEST_DUCKLAKE=true for real extension tests"
  )
  f <- fixture("ducklake")
  on.exit(unlink(f$root, recursive = TRUE))
  first <- run(f$pipeline, f$lake)
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  expect_equal(
    run(f$pipeline, f$lake, stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_equal(measure(f$lake, reserve_metric())$value, 300)
  config <- f$lake$config
  disconnect_lake(f$lake)
  lake <- connect_lake(config)
  on.exit(disconnect_lake(lake), add = TRUE)
  expect_equal(
    sum(
      dplyr::collect(tbl(lake, "risk.validated", first$release_id))$reserve
    ),
    300
  )
})

test_that("pointblank runs actual checks including inactive/error steps", {
  skip_if_not_installed("pointblank")
  f <- fixture()
  on.exit(fixture_cleanup(f))
  contract <- f$contract
  contract$rules <- list(pointblank_checks("reserve", function(x) {
    pointblank::create_agent(x) |>
      pointblank::col_vals_gte(columns = "reserve", value = 0)
  }))
  expect_true(tidyweave:::quality_ok(validate(f$good, contract)))
  bad <- f$good
  bad$reserve[1] <- -1
  expect_false(tidyweave:::quality_ok(validate(bad, contract)))
  contract$rules <- list(pointblank_checks("inactive", function(x) {
    pointblank::create_agent(x) |>
      pointblank::col_vals_gte(columns = "reserve", value = 0, active = FALSE)
  }))
  expect_false(tidyweave:::quality_ok(validate(f$good, contract)))
})

test_that("dm adapter checks keys on pinned tables", {
  skip_if_not_installed("dm")
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  model <- model(
    f$lake,
    c(reserves = "risk.validated"),
    list(reserves = c("id", "date"))
  )
  expect_s3_class(model, "dm")
  expect_length(attr(model, "tw_releases"), 1)
})
