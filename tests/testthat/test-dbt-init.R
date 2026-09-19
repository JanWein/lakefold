test_that("starter profiles attach the configured catalog", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  for (backend in c("duckdb", "ducklake")) {
    config <- dl_config(
      dl_catalog_duckdb(file.path(root, "lake.db")),
      dl_storage_local(file.path(root, "data")),
      backend = backend
    )
    project <- dl_dbt_init(file.path(root, backend), config)
    profile <- yaml::read_yaml(file.path(
      project$path,
      "profiles.yml"
    ))$lakefold_demo$outputs$dev
    expect_equal(profile$database, "lake")
    expect_equal(profile$attach[[1]]$alias, "lake")
    expect_equal(
      profile$attach[[1]]$path,
      paste0(
        if (backend == "ducklake") "ducklake:" else "",
        config$catalog$path
      )
    )
    expect_equal(file.exists(config$catalog$path), FALSE)
  }
})

test_that("starter refuses to overwrite existing files", {
  root <- withr::local_tempdir()
  writeLines("keep", file.path(root, "important.txt"))
  expect_snapshot(
    error = TRUE,
    dl_dbt_init(root, dl_config(backend = "duckdb"))
  )
  expect_equal(readLines(file.path(root, "important.txt")), "keep")
})

test_that("real dbt builds and tests the starter project", {
  executable <- Sys.getenv("LAKEFOLD_DBT_EXECUTABLE")
  skip_if(
    !nzchar(executable),
    "Set LAKEFOLD_DBT_EXECUTABLE for the external CLI integration test"
  )
  root <- withr::local_tempdir()
  backend <- Sys.getenv("DATALOOM_TEST_BACKEND", "duckdb")
  config <- dl_config(
    dl_catalog_duckdb(file.path(root, "lake.db")),
    dl_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = backend
  )
  lake <- dl_connect(config)
  dl_disconnect(lake)
  project <- dl_dbt_init(
    file.path(root, "dbt"),
    config,
    executable = executable
  )
  result <- dl_dbt_build(project, echo = FALSE, stop_on_failure = FALSE)
  expect_equal(
    result$success,
    TRUE,
    info = paste(result$stdout, result$stderr, result$artifact_error)
  )
  if (!result$success) {
    return(invisible(NULL))
  }
  expect_equal(sum(result$results$status == "pass"), 5L)
  expect_equal(dl_dbt_test(project, echo = FALSE)$success, TRUE)
  lake <- dl_connect(config)
  withr::defer(dl_disconnect(lake))
  model <- dl_dbt_model(
    lake,
    result,
    tables = c(revenue = "model.lakefold_demo.customer_revenue"),
    primary_keys = list(revenue = "customer_id")
  )
  expect_equal(sum(dplyr::collect(model$revenue)$revenue), 150)
})
