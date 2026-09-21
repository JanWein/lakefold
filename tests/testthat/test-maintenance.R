test_that("cleanup previews by default and preserves releases and diagnostics", {
  f <- fixture()
  withr::defer(fixture_cleanup(f))
  good <- tw_run(f$pipeline, f$lake)
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  failed <- tw_run(f$pipeline, f$lake, stop_on_failure = FALSE)
  reference_time <- Sys.time() + 40 * 86400
  plan <- tw_cleanup(f$lake, at = reference_time)
  expect_equal(nrow(plan), 2L)
  expect_equal(unique(plan$run_id), failed$run_id)
  expect_equal(all(plan$action == "would_drop"), TRUE)
  expect_equal(
    nrow(tw_quality(f$lake, run_id = failed$run_id)),
    nrow(failed$quality)
  )
  removed <- tw_cleanup(f$lake, at = reference_time, dry_run = FALSE)
  expect_equal(removed$action, rep("dropped", 2))
  expect_equal(nrow(tw_cleanup(f$lake, at = reference_time)), 0L)
  expect_equal(
    dplyr::collect(tw_tbl(f$lake, "risk.validated", good$release_id))$reserve,
    f$good$reserve
  )
  expect_equal(
    nrow(tw_quality(f$lake, run_id = failed$run_id)),
    nrow(failed$quality)
  )
})
