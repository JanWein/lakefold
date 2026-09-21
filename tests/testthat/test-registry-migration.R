test_that("legacy quality evidence survives an idempotent registry migration", {
  f <- fixture()
  withr::defer(fixture_cleanup(f))
  first <- tw_run(f$pipeline, f$lake)
  for (name in c("engine", "stage", "segment", "details")) {
    DBI::dbExecute(
      f$lake$con,
      paste("ALTER TABLE lake._dl.quality_results DROP COLUMN", name)
    )
  }
  DBI::dbExecute(f$lake$con, "DROP TABLE lake._dl.schema_version")
  tidyweave:::registry_init(f$lake)
  tidyweave:::registry_init(f$lake)
  evidence <- tw_quality(f$lake, run_id = first$run_id)
  expect_equal(evidence$engine, rep("legacy", nrow(first$quality)))
  expect_equal(evidence$stage, rep("candidate", nrow(first$quality)))
  expect_equal(tw_registry(f$lake, "schema_version")$version, 4L)
  expect_equal(tw_releases(f$lake)$release_id, first$release_id)
  DBI::dbExecute(f$lake$con, "UPDATE lake._dl.schema_version SET version = 999")
  expect_snapshot(error = TRUE, tidyweave:::registry_init(f$lake))
})
