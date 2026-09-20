test_that("quality accessors distinguish latest failure, pinned release and cache", {
  f <- fixture()
  withr::defer(fixture_cleanup(f))
  first <- run(f$pipeline, f$lake)
  cached <- run(f$pipeline, f$lake)
  expect_equal(
    quality(f$lake, run_id = cached$run_id)$run_id,
    rep(first$run_id, nrow(first$quality))
  )
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  run(f$pipeline, f$lake, stop_on_failure = FALSE)
  expect_equal(
    any(quality(f$lake, asset = "risk.validated")$status == "failed"),
    TRUE
  )
  expect_quality(quality(
    f$lake,
    asset = "risk.validated",
    release = first$release_id
  ))
  expect_equal(status(f$lake, "risk.validated")$status[[1]], "blocked")
  expect_equal(status(first)$success, TRUE)
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
  expect_equal(tail(status(result)$id, 1), ".process")
  expect_equal(tidyweave:::quality_ok(quality(result)), FALSE)
  edges <- lineage(result, "seed.shop.raw_orders", direction = "downstream")
  expect_equal(nrow(edges), 2L)
  expect_equal(
    nrow(lineage(
      result,
      "seed.shop.raw_orders",
      direction = "downstream",
      recursive = FALSE
    )),
    1L
  )
})
