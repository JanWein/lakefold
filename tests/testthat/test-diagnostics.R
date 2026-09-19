test_that("quality accessors distinguish latest failure, pinned release and cache", {
  f <- fixture()
  withr::defer(cleanup(f))
  first <- dl_run(f$pipeline, f$lake)
  cached <- dl_run(f$pipeline, f$lake)
  expect_equal(
    dl_quality(f$lake, run_id = cached$run_id)$run_id,
    rep(first$run_id, nrow(first$quality))
  )
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  dl_run(f$pipeline, f$lake, stop_on_failure = FALSE)
  expect_equal(
    any(dl_quality(f$lake, asset = "risk.validated")$status == "failed"),
    TRUE
  )
  dl_expect_quality(dl_quality(
    f$lake,
    asset = "risk.validated",
    release = first$release_id
  ))
  expect_equal(dl_status(f$lake, "risk.validated")$status[[1]], "blocked")
  expect_equal(dl_status(first)$success, TRUE)
})

test_that("process errors stay visible beside successful dbt nodes", {
  parsed <- lakefold:::dbt_read_artifacts(system.file(
    "extdata",
    "dbt-artifacts",
    package = "lakefold"
  ))
  result <- structure(
    list(
      success = FALSE,
      status = 2L,
      command = "build",
      results = parsed$results,
      manifest = parsed$manifest
    ),
    class = "dl_dbt_result"
  )
  expect_equal(tail(dl_status(result)$id, 1), ".process")
  expect_equal(lakefold:::quality_ok(dl_quality(result)), FALSE)
  edges <- dl_lineage(result, "seed.shop.raw_orders", direction = "downstream")
  expect_equal(nrow(edges), 2L)
  expect_equal(
    nrow(dl_lineage(
      result,
      "seed.shop.raw_orders",
      direction = "downstream",
      recursive = FALSE
    )),
    1L
  )
})
