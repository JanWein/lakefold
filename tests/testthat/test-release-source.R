test_that("config release sources read approved dbt output without registry changes", {
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  DBI::dbExecute(lake$con, "CREATE SCHEMA lake.marts")
  DBI::dbExecute(
    lake$con,
    paste(
      "CREATE TABLE lake.marts.customer_revenue AS",
      "SELECT 101 AS customer_id, 100.0::DOUBLE AS revenue"
    )
  )
  artifacts <- dbt_read_artifacts(system.file(
    "extdata",
    "dbt-artifacts",
    package = "tidyweave"
  ))
  build <- structure(
    list(
      success = TRUE,
      status = 0L,
      command = "build",
      results = artifacts$results,
      manifest = artifacts$manifest
    ),
    class = "tw_dbt_result"
  )
  config <- lake$config
  tw_close_lake(lake)
  approved <- tw_dbt_publish(config, build, "customer_revenue")
  checksum <- digest::digest(file = config$catalog$path, algo = "sha256")
  source <- tw_source_release(config, approved$asset, approved$release_id)
  expect_equal(tw_inspect(source)$backend, config$backend)
  expect_false(tw_capabilities(source)$lazy)
  expect_false(source$lake$read_only)
  read <- tw_read_source(source)
  expect_s3_class(read, "tbl_df")
  expect_equal(read$revenue, 100)
  expect_equal(attr(read, "tw_input_reference")$release_id, approved$release_id)
  expect_equal(
    digest::digest(file = config$catalog$path, algo = "sha256"),
    checksum
  )
  result <- tw_product("export") |> tw_add_source(source) |> tw_run()
  expect_equal(tw_collect(result)$revenue, 100)
  expect_equal(result$inputs$release_id, approved$release_id)
  expect_equal(result$inputs$asset, approved$asset)
  destination <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(destination, shutdown = TRUE))
  exported <- tw_product("database_export") |>
    tw_add_source(source) |>
    tw_set_target(tw_target_database(destination, "approved")) |>
    tw_run()
  expect_equal(DBI::dbReadTable(destination, "approved")$revenue, 100)
  expect_equal(exported$inputs$release_id, approved$release_id)
  expect_equal(
    digest::digest(file = config$catalog$path, algo = "sha256"),
    checksum
  )
  # Reopening writable proves the adapter closed its read-only attachment.
  writable <- tw_connect_lake(config)
  withr::defer(tw_close_lake(writable))
  expect_true(DBI::dbIsValid(writable$con))
  expect_equal(nrow(tw_registry(writable, "runs")), 1L)
})

test_that("config source pins remain unchanged after later publications", {
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  config <- lake$config
  first <- tw_ingest(data.frame(id = 1L), lake, "orders")
  pinned <- tw_source_release(config, "orders", first$release_id)
  tw_close_lake(lake)
  later <- tw_ingest(data.frame(id = 2L), config, "orders")
  data <- tw_read_source(pinned)
  expect_equal(data$id, 1L)
  expect_equal(attr(data, "tw_input_reference")$release_id, first$release_id)
  latest <- tw_read_source(tw_source_release(config, "orders"))
  expect_equal(latest$id, 2L)
  expect_equal(attr(latest, "tw_input_reference")$release_id, later$release_id)
  expect_equal(tw_collect(first)$id, 1L)
})

test_that("latest is resolved once and records that release on both source forms", {
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  accepted <- tw_ingest(data.frame(id = 1L), lake, "orders")
  connected <- tw_source_release(lake, "orders")
  config <- lake$config
  actual_resolver <- resolve_release
  calls <- 0L
  testthat::local_mocked_bindings(
    resolve_release = function(...) {
      calls <<- calls + 1L
      actual_resolver(...)
    },
    .package = "tidyweave"
  )
  lazy <- tw_read_source(connected)
  expect_equal(calls, 1L)
  expect_equal(attr(lazy, "tw_input_reference")$release_id, accepted$release_id)
  expect_s3_class(lazy, "tbl_sql")
  expect_true(tw_capabilities(connected)$lazy)
  expect_true(DBI::dbIsValid(lake$con))
  expect_equal(tw_collect(lazy)$id, 1L)
  tw_close_lake(lake)
  calls <- 0L
  eager <- tw_read_source(tw_source_release(config, "orders"))
  expect_equal(calls, 1L)
  expect_equal(
    attr(eager, "tw_input_reference")$release_id,
    accepted$release_id
  )
  expect_s3_class(eager, "tbl_df")
})

test_that("config source provenance survives publication into a different lake", {
  root <- withr::local_tempdir()
  original <- tw_open_lake(file.path(root, "source"))
  withr::defer(tw_close_lake(original))
  first <- tw_ingest(data.frame(id = 1L), original, "original")
  config <- original$config
  tw_close_lake(original)
  destination <- tw_open_lake(file.path(root, "destination"))
  withr::defer(tw_close_lake(destination))
  result <- tw_product("orders") |>
    tw_add_source(tw_source_release(config, "original", first$release_id)) |>
    tw_set_target(destination) |>
    tw_run()
  expect_equal(tw_collect(result)$id, 1L)
  edges <- tw_registry(destination, "lineage_edges")
  expect_true(any(
    edges$from_id == "original" &
      edges$from_version == first$release_id &
      edges$to_id == "orders"
  ))
})

test_that("construction and validation create no storage and reject invalid inputs", {
  root <- file.path(withr::local_tempdir(), "absent")
  config <- tw_lake_config(
    tw_registry_duckdb(file.path(root, "lake.db")),
    tw_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  source <- tw_source_release(config, "orders")
  expect_false(dir.exists(root))
  expect_invisible(tw_check_component(source))
  expect_false(dir.exists(root))
  expect_error(tw_read_source(source), "read-only catalog must already exist")
  expect_false(dir.exists(root))
  expect_error(
    tw_source_release(list(), "orders"),
    "connected lake or lake_config"
  )
  invalid <- config
  invalid$backend <- "unsupported"
  expect_error(tw_source_release(invalid, "orders"), "arg")
  expect_error(tw_source_release(config, "orders", character()), "release_id")
  testthat::local_mocked_bindings(
    need = function(package) {
      stop("Install optional package: duckdb")
    },
    .package = "tidyweave"
  )
  expect_error(
    tw_source_release(config, "orders"),
    "Install optional package: duckdb"
  )
  expect_false(dir.exists(root))
})

test_that("read-only failures preserve existing files and release handles close", {
  root <- withr::local_tempdir()
  path <- file.path(root, "empty.db")
  con <- DBI::dbConnect(duckdb::duckdb(), path)
  DBI::dbDisconnect(con, shutdown = TRUE)
  config <- tw_lake_config(
    tw_registry_duckdb(path),
    tw_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb",
    read_only = TRUE
  )
  checksum <- digest::digest(file = path, algo = "sha256")
  expect_error(
    tw_read_source(tw_source_release(config, "orders")),
    "Registry is missing"
  )
  expect_equal(digest::digest(file = path, algo = "sha256"), checksum)
  expect_false(dir.exists(config$landing))
  expect_false(dir.exists(config$storage$path))
  lake <- tw_open_lake(file.path(root, "initialized"))
  withr::defer(tw_close_lake(lake))
  accepted <- tw_ingest(data.frame(id = 1L), lake, "orders")
  config <- lake$config
  source <- tw_source_release(lake, "orders")
  tw_close_lake(lake)
  expect_error(tw_read_source(source), "connected tw_lake")
  expect_error(
    tw_read_source(tw_source_release(config, "orders", "unknown")),
    class = "tw_no_release"
  )
  config$read_only <- TRUE
  expect_equal(
    tw_read_source(tw_source_release(config, "orders", accepted$release_id))$id,
    1L
  )
  reopened <- tw_connect_lake(config, read_only = FALSE)
  withr::defer(tw_close_lake(reopened))
  expect_true(DBI::dbIsValid(reopened$con))
})

test_that("config sources reuse the same publication lake without a second attachment", {
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  config <- lake$config
  original <- tw_ingest(data.frame(id = 1L), lake, "original")
  source_config <- config
  source_config$read_only <- TRUE
  source <- tw_source_release(source_config, "original", original$release_id)
  from_open <- tw_product("connected_copy") |>
    tw_add_source(source) |>
    tw_set_target(lake) |>
    tw_run()
  expect_equal(tw_collect(from_open)$id, 1L)
  expect_true(DBI::dbIsValid(lake$con))
  tw_close_lake(lake)
  from_config <- tw_product("config_copy") |>
    tw_add_source(source) |>
    tw_set_target(config) |>
    tw_run()
  expect_equal(tw_collect(from_config)$id, 1L)
  ingested <- tw_ingest(source, config, "raw_copy")
  expect_equal(tw_collect(ingested)$id, 1L)
  expect_equal(
    ingested$inputs$source_version[
      ingested$inputs$source == "original"
    ],
    original$release_id
  )
  reader <- tw_connect_lake(config, read_only = TRUE)
  withr::defer(tw_close_lake(reader))
  edges <- tw_registry(reader, "lineage_edges")
  expect_setequal(
    edges$to_id[edges$from_id == "original"],
    c("connected_copy", "config_copy", "raw_copy")
  )
})

test_that("release-source subclasses keep their custom read method", {
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  source <- tw_source_release(lake$config, "custom")
  class(source) <- c("custom_release_source", class(source))
  calls <- 0L
  local_adapter_method(
    "tw_read_source",
    "custom_release_source",
    function(source) {
      calls <<- calls + 1L
      data.frame(id = 42L)
    }
  )
  result <- tw_product("custom_export") |>
    tw_add_source(source) |>
    tw_set_target(lake) |>
    tw_run()
  expect_equal(tw_collect(result)$id, 42L)
  expect_equal(calls, 1L)
  result <- tw_ingest(source, lake, "custom_raw")
  expect_equal(tw_collect(result)$id, 42L)
  expect_equal(calls, 2L)
})
