test_that("quality accessors distinguish latest failure, pinned release and cache", {
  f <- fixture()
  withr::defer(fixture_cleanup(f))
  first <- tw_run(f$pipeline, f$lake)
  cached <- tw_run(f$pipeline, f$lake)
  expect_equal(
    tw_quality(f$lake, run_id = cached$run_id)$run_id,
    rep(first$run_id, nrow(first$quality))
  )
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  tw_run(f$pipeline, f$lake, stop_on_failure = FALSE)
  expect_equal(
    any(tw_quality(f$lake, asset = "risk.validated")$status == "failed"),
    TRUE
  )
  tw_expect_quality(tw_quality(
    f$lake,
    asset = "risk.validated",
    release = first$release_id
  ))
  expect_equal(tw_status(f$lake, "risk.validated")$status[[1]], "blocked")
  expect_equal(tw_status(first)$success, TRUE)
})

test_that("process errors stay visible beside successful dbt nodes", {
  parsed <- tidyweave:::dbt_read_artifacts(system.file(
    "extdata",
    "dbt-artifacts",
    package = "tidyweave"
  ))
  result <- structure(
    list(
      success = FALSE,
      status = 2L,
      command = "build",
      results = parsed$results,
      manifest = parsed$manifest
    ),
    class = "tw_dbt_result"
  )
  expect_equal(tail(tw_status(result)$id, 1), ".process")
  expect_equal(tidyweave:::quality_ok(tw_quality(result)), FALSE)
  edges <- tw_lineage(result, "seed.shop.raw_orders", direction = "downstream")
  expect_equal(nrow(edges), 2L)
  expect_equal(
    nrow(tw_lineage(
      result,
      "seed.shop.raw_orders",
      direction = "downstream",
      recursive = FALSE
    )),
    1L
  )
})
