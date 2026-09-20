test_that("cleanup previews by default and preserves releases and diagnostics", {
  f <- fixture()
  withr::defer(fixture_cleanup(f))
  good <- run(f$pipeline, f$lake)
  bad <- f$good
  bad$reserve[1] <- -1
  f$write(bad)
  failed <- run(f$pipeline, f$lake, stop_on_failure = FALSE)
  reference_time <- Sys.time() + 40 * 86400
  plan <- cleanup(f$lake, at = reference_time)
  expect_equal(nrow(plan), 2L)
  expect_equal(unique(plan$run_id), failed$run_id)
  expect_equal(all(plan$action == "would_drop"), TRUE)
  expect_equal(
    nrow(quality(f$lake, run_id = failed$run_id)),
    nrow(failed$quality)
  )
  removed <- cleanup(f$lake, at = reference_time, dry_run = FALSE)
  expect_equal(removed$action, rep("dropped", 2))
  expect_equal(nrow(cleanup(f$lake, at = reference_time)), 0L)
  expect_equal(
    dplyr::collect(tbl(f$lake, "risk.validated", good$release_id))$reserve,
    f$good$reserve
  )
  expect_equal(
    nrow(quality(f$lake, run_id = failed$run_id)),
    nrow(failed$quality)
  )
})
