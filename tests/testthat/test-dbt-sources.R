dbt_source_result <- function(config, asset = "orders", release = "release_1") {
  structure(
    list(
      status = "published",
      run_id = "run_1",
      asset = asset,
      release_id = release,
      output_config = config,
      outputs = list(
        type = "lake release",
        database = "lake",
        schema = "raw",
        table = paste0("table_", release),
        asset = asset,
        release_id = release
      )
    ),
    class = "tw_run_result"
  )
}

test_that("dbt sources pin exact relations and explicitly refresh logical names", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  writeLines("name: example", file.path(root, "dbt_project.yml"))
  project <- dbt_project(root)
  config <- lake_config(backend = "duckdb")
  orders <- dbt_source_result(config)
  customers <- dbt_source_result(config, "customers", "release_c")
  expect_identical(
    dbt_sources(project, list(orders = orders, customers = customers)),
    project
  )
  path <- file.path(root, "models", "tidyweave_sources_raw.yml")
  source <- yaml::read_yaml(path)$sources[[1]]
  expect_identical(source$database, "lake")
  expect_identical(source$schema, "raw")
  expect_identical(source$tables[[1]]$identifier, "table_release_1")
  expect_identical(
    source$tables[[1]]$config$meta$tidyweave$release_id,
    "release_1"
  )
  expect_true(all(unlist(source$quoting)))
  newer <- dbt_source_result(config, release = "release_2")
  dbt_sources(project, list(orders = newer))
  tables <- yaml::read_yaml(path)$sources[[1]]$tables
  by_name <- stats::setNames(tables, vapply(tables, `[[`, character(1), "name"))
  expect_identical(by_name$orders$identifier, "table_release_2")
  expect_identical(by_name$customers$identifier, "table_release_c")
  expect_length(list.files(root, recursive = TRUE, pattern = "\\.sql$"), 0L)
})

test_that("rejected or unqualified sources preserve the previous source file", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  writeLines("name: example", file.path(root, "dbt_project.yml"))
  project <- dbt_project(root)
  accepted <- dbt_source_result(lake_config(backend = "duckdb"))
  dbt_sources(project, list(orders = accepted))
  path <- file.path(root, "models", "tidyweave_sources_raw.yml")
  previous <- readBin(path, "raw", n = file.info(path)$size)
  rejected <- accepted
  rejected$status <- "blocked"
  unqualified <- accepted
  unqualified$outputs$table <- NULL
  nonraw <- accepted
  nonraw$outputs$schema <- "marts"
  mismatched <- accepted
  mismatched$release_id <- "different"
  mutable <- accepted
  mutable$outputs$type <- "database"
  for (bad in list(rejected, unqualified, nonraw, mismatched, mutable)) {
    expect_error(
      dbt_sources(project, list(orders = accepted, bad = bad)),
      "successful, qualified immutable RAW",
      class = "tw_dbt_invalid"
    )
    expect_identical(readBin(path, "raw", n = file.info(path)$size), previous)
  }
  expect_error(dbt_sources(project, list(accepted)), "named, non-empty")
  expect_error(
    dbt_sources(project, list(orders = accepted, orders = accepted)),
    "named, non-empty"
  )
})

test_that("dbt sources protect user-owned YAML and catalog identity", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  writeLines("name: example", file.path(root, "dbt_project.yml"))
  dir.create(file.path(root, "models"))
  path <- file.path(root, "models", "tidyweave_sources_raw.yml")
  writeLines("# My source definitions", path)
  config <- lake_config(backend = "duckdb")
  project <- dbt_project(root)
  accepted <- dbt_source_result(config)
  expect_error(
    dbt_sources(project, list(orders = accepted)),
    "not package-owned"
  )
  expect_identical(readLines(path), "# My source definitions")
  other <- accepted
  other$output_config$catalog$path <- file.path(root, "other.db")
  expect_error(
    dbt_sources(project, list(orders = accepted, other = other)),
    "same catalog"
  )
  project$source_config <- config
  expect_error(
    dbt_sources(project, list(orders = other)),
    "different project catalog"
  )
  ducklake <- lake_config(backend = "ducklake")
  alternative <- ducklake
  alternative$storage$path <- file.path(root, "other-data")
  expect_false(identical(
    dbt_catalog_fingerprint(ducklake),
    dbt_catalog_fingerprint(alternative)
  ))
})
