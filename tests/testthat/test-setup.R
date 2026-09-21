test_that("unsupported local formats are rejected without rewriting configuration", {
  root <- withr::local_tempdir()
  marker <- file.path(root, "tidyweave.json")
  content <- '{"format":1,"backend":"duckdb"}'
  writeLines(content, marker)
  expect_snapshot(error = TRUE, tw_lake_config(path = root))
  expect_identical(readLines(marker), content)
})

test_that("corrupt current layer settings are rejected without rewriting them", {
  root <- withr::local_tempdir()
  marker <- file.path(root, "tidyweave.json")
  content <- '{"format":2,"backend":"duckdb","layers":["raw","raw"]}'
  writeLines(content, marker)
  expect_snapshot(error = TRUE, tw_lake_config(path = root))
  expect_identical(readLines(marker), content)
})
