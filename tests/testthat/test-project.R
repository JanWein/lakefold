test_that("a minimal project runs without optional infrastructure", {
  root <- withr::local_tempdir()
  path <- file.path(root, "orders")
  created <- dr_init_project(path)
  expect_equal(created, normalizePath(path, winslash = "/", mustWork = TRUE))
  withr::local_dir(path)
  environment <- new.env(parent = globalenv())
  sys.source("run.R", envir = environment)
  expect_equal(readRDS("output.rds")$amount, c(50, 150, 100))
  expect_equal(environment$result$status, "completed")
  expect_equal(nrow(dr_run_history(".dataraft/evidence")), 1L)
  expect_equal(file.exists("_targets.R"), FALSE)
  expect_equal(file.exists("renv.lock"), FALSE)
})

test_that("optional project files are explicit and existing work is protected", {
  root <- withr::local_tempdir()
  dr_init_project(
    root,
    name = "orders.monthly",
    renv = TRUE,
    targets = TRUE,
    connect = TRUE
  )
  expect_equal(
    file.exists(file.path(
      root,
      c("_targets.R", "init-renv.R", "job.qmd", ".gitignore")
    )),
    rep(TRUE, 4)
  )
  for (file in list.files(root, pattern = "\\.R$", full.names = TRUE)) {
    expect_type(parse(file), "expression")
  }
  expect_equal(file.exists(file.path(root, "renv.lock")), FALSE)
  before <- readLines(file.path(root, "definitions.R"))
  error <- tryCatch(dr_init_project(root), error = identity)
  expect_match(conditionMessage(error), "never overwritten", fixed = TRUE)
  expect_equal(readLines(file.path(root, "definitions.R")), before)
})
