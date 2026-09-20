test_that("starter profiles attach the configured catalog", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  for (backend in c("duckdb", "ducklake")) {
    config <- lake_config(
      registry_duckdb(file.path(root, "lake.db")),
      storage_local(file.path(root, "data")),
      backend = backend
    )
    project <- dbt_init(file.path(root, backend), config)
    profile <- yaml::read_yaml(file.path(
      project$path,
      "profiles.yml"
    ))$tidyweave_demo$outputs$dev
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
    dbt_init(root, lake_config(backend = "duckdb"))
  )
  expect_equal(readLines(file.path(root, "important.txt")), "keep")
})

test_that("real dbt builds and tests the starter project", {
  executable <- Sys.getenv("TIDYWEAVE_DBT_EXECUTABLE")
  skip_if(
    !nzchar(executable),
    "Set TIDYWEAVE_DBT_EXECUTABLE for the external CLI integration test"
  )
  root <- withr::local_tempdir()
  backend <- Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  config <- lake_config(
    registry_duckdb(file.path(root, "lake.db")),
    storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = backend
  )
  lake <- connect_lake(config)
  disconnect_lake(lake)
  project <- dbt_init(
    file.path(root, "dbt"),
    config,
    executable = executable
  )
  result <- dbt_build(project, echo = FALSE, stop_on_failure = FALSE)
  expect_equal(
    result$success,
    TRUE,
    info = paste(result$stdout, result$stderr, result$artifact_error)
  )
  if (!result$success) {
    return(invisible(NULL))
  }
  expect_equal(sum(result$results$status == "pass"), 5L)
  expect_equal(dbt_test(project, echo = FALSE)$success, TRUE)
  lake <- connect_lake(config)
  withr::defer(disconnect_lake(lake))
  model <- dbt_model(
    lake,
    result,
    tables = c(revenue = "model.tidyweave_demo.customer_revenue"),
    primary_keys = list(revenue = "customer_id")
  )
  expect_equal(sum(dplyr::collect(model$revenue)$revenue), 150)
  contract <- contract_from(
    model$revenue,
    "revenue",
    "Analytics",
    "Customer revenue",
    "One customer",
    key = "customer_id"
  ) |>
    contract_confirm()
  release <- dbt_publish(
    lake,
    result,
    "model.tidyweave_demo.customer_revenue",
    contract,
    "shop.revenue",
    code_version = "v1"
  )
  expect_equal(release$status, "published")
  expect_equal(
    sum(
      dplyr::collect(tbl(lake, "shop.revenue", release$release_id))$revenue
    ),
    150
  )
})
