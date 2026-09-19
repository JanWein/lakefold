test_that("legacy quality evidence survives an idempotent registry migration", {
  f <- fixture()
  withr::defer(cleanup(f))
  first <- dl_run(f$pipeline, f$lake)
  for (name in c("engine", "stage", "segment", "details")) {
    DBI::dbExecute(
      f$lake$con,
      paste("ALTER TABLE lake._dl.quality_results DROP COLUMN", name)
    )
  }
  DBI::dbExecute(f$lake$con, "DROP TABLE lake._dl.schema_version")
  lakefold:::registry_init(f$lake)
  lakefold:::registry_init(f$lake)
  evidence <- dl_quality(f$lake, run_id = first$run_id)
  expect_equal(evidence$engine, rep("legacy", nrow(first$quality)))
  expect_equal(evidence$stage, rep("candidate", nrow(first$quality)))
  expect_equal(dl_registry(f$lake, "schema_version")$version, 2L)
  expect_equal(dl_releases(f$lake)$release_id, first$release_id)
  DBI::dbExecute(f$lake$con, "UPDATE lake._dl.schema_version SET version = 999")
  expect_snapshot(error = TRUE, lakefold:::registry_init(f$lake))
})
