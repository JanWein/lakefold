test_that("partition replacement retains other periods and validates global keys", {
  f <- fixture()
  on.exit(cleanup(f))
  f$pipeline$steps$publish$mode <- "replace_partition"
  f$pipeline$steps$publish$partition_by <- "date"
  a <- dl_run(f$pipeline, f$lake)
  sep <- f$good
  sep$date <- as.Date("2026-09-30")
  sep$reserve <- c(400, 500)
  f$write(sep)
  b <- dl_run(f$pipeline, f$lake)
  expect_equal(nrow(dplyr::collect(dl_tbl(f$lake, "risk.validated"))), 4)
  fixed <- f$good
  fixed$reserve <- c(150, 250)
  f$write(fixed)
  dl_run(f$pipeline, f$lake)
  current <- dplyr::collect(dl_tbl(f$lake, "risk.validated"))
  expect_equal(nrow(current), 4)
  expect_equal(sum(current$reserve), 1300)
  expect_equal(
    nrow(dplyr::collect(dl_tbl(f$lake, "risk.validated", a$release_id))),
    2
  )
  expect_equal(
    sum(dplyr::collect(dl_tbl(f$lake, "risk.validated", b$release_id))$reserve),
    1200
  )
  f$write(f$good[0, ])
  expect_equal(
    dl_run(f$pipeline, f$lake, stop_on_failure = FALSE)$status,
    "error"
  )
})

test_that("publication transaction rolls back release and successful run together", {
  f <- fixture()
  on.exit(cleanup(f))
  first <- dl_run(f$pipeline, f$lake)
  run <- lakefold:::new_run(f$lake, "test", "risk.validated", "d", "v")
  raw <- lakefold:::materialize(f$lake, f$good, "raw", "rollback_raw")
  pub <- f$pipeline$steps$publish
  candidate <- lakefold:::compose_candidate(f$lake, raw, pub, run)
  quality <- dl_validate(candidate$data, f$contract)
  expect_error(
    lakefold:::publish_candidate(
      f$lake,
      run,
      pub,
      candidate,
      f$contract,
      quality,
      "d",
      "i",
      NA_character_,
      list(),
      before_commit = function() stop("simulated crash before commit")
    ),
    "simulated crash"
  )
  expect_equal(nrow(dl_registry(f$lake, "releases")), 1)
  expect_equal(
    dl_registry(f$lake, "runs")$status[
      dl_registry(f$lake, "runs")$run_id == run
    ],
    "running"
  )
  expect_equal(dl_run(f$pipeline, f$lake)$release_id, first$release_id)
})
