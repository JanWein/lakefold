test_that("custom layers survive folder reopening and permit another publication", {
  root <- file.path(withr::local_tempdir(), "lake")
  layers <- c("raw", "staging", "core", "marts")
  lake <- connect_lake(lake_config(path = root, layers = layers))
  first <- publish(
    product("orders", data.frame(amount = 350)),
    to = lake,
    layer = "core"
  )
  close_lake(lake)
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  expect_identical(lake$config$layers, layers)
  expect_equal(read_release(lake, "orders")$amount, 350)
  second <- publish(
    product("orders", data.frame(amount = 380)),
    to = lake,
    layer = "core"
  )
  expect_identical(second$status, "published")
  expect_equal(read_release(lake, "orders", first$release_id)$amount, 350)
  schemas <- DBI::dbGetQuery(
    lake$con,
    "SELECT schema_name FROM information_schema.schemata WHERE catalog_name = 'lake'"
  )$schema_name
  expect_setequal(setdiff(schemas, c("main", "_dl")), layers)
})

test_that("both folder entry points retain named roles and read-only opens do not write", {
  root <- file.path(withr::local_tempdir(), "lake")
  layers <- c(
    raw = "raw",
    staging = "prep",
    core = "business",
    marts = "reporting"
  )
  lake <- setup_lake(path = root, layers = layers, backend = "duckdb")
  close_lake(lake)
  marker <- file.path(root, "tidyweave.json")
  before <- readLines(marker)
  config <- lake_config(path = root)
  expect_identical(config$layers, layers)
  lake <- open_lake(root, read_only = TRUE)
  expect_identical(lake$config$layers, layers)
  close_lake(lake)
  expect_identical(readLines(marker), before)
  lake <- setup_lake(path = root)
  expect_identical(lake$config$layers, layers)
  close_lake(lake)
  expect_snapshot(error = TRUE, open_lake(root, layers = c("raw", "products")))
  expect_snapshot(error = TRUE, setup_lake(path = root, landing = "elsewhere"))
  expect_snapshot(error = TRUE, open_lake(root, backend = "ducklake"))
  expect_identical(readLines(marker), before)
})

test_that("older custom folders require explicit one-time recovery without adding schemas", {
  root <- file.path(withr::local_tempdir(), "lake")
  layers <- c("raw", "staging", "core", "marts")
  lake <- open_lake(root, layers = layers)
  close_lake(lake)
  marker <- file.path(root, "tidyweave.json")
  old <- '{"format":1,"backend":"duckdb"}'
  writeLines(old, marker)
  expect_snapshot(error = TRUE, open_lake(root))
  expect_identical(readLines(marker), old)
  lake <- open_lake(root, layers = layers, read_only = TRUE)
  expect_identical(lake$config$layers, layers)
  close_lake(lake)
  expect_identical(readLines(marker), old)
  lake <- open_lake(root, layers = layers)
  schemas <- DBI::dbGetQuery(
    lake$con,
    "SELECT schema_name FROM information_schema.schemata WHERE catalog_name = 'lake'"
  )$schema_name
  close_lake(lake)
  expect_setequal(setdiff(schemas, c("main", "_dl")), layers)
  expect_identical(lake_config(path = root)$layers, layers)
})

test_that("old default folders upgrade and corrupt saved layers are rejected", {
  root <- withr::local_tempdir()
  lake <- open_lake(root)
  close_lake(lake)
  marker <- file.path(root, "tidyweave.json")
  writeLines('{"format":1,"backend":"duckdb"}', marker)
  config <- lake_config(path = root)
  lake <- connect_lake(config)
  DBI::dbExecute(lake$con, "CREATE SCHEMA lake.extra")
  close_lake(lake)
  lake <- connect_lake(config)
  close_lake(lake)
  expect_identical(jsonlite::fromJSON(marker)$format, 2L)
  writeLines('{"format":2,"backend":"duckdb","layers":["raw","raw"]}', marker)
  before <- readLines(marker)
  expect_snapshot(error = TRUE, open_lake(root))
  expect_identical(readLines(marker), before)
})

test_that("a single layer is preserved without JSON scalar conversion", {
  root <- withr::local_tempdir()
  lake <- open_lake(root, layers = "raw")
  close_lake(lake)
  expect_identical(lake_config(path = root)$layers, "raw")
})

test_that("saved configuration cannot be bypassed by an older definition", {
  root <- withr::local_tempdir()
  stale <- lake_config(path = root)
  lake <- open_lake(root, layers = c("raw", "core"))
  close_lake(lake)
  expect_snapshot(error = TRUE, connect_lake(stale))
})

test_that("DuckLake folder setup survives reconnect and another checked publication", {
  skip_if(
    Sys.getenv("TIDYWEAVE_TEST_DUCKLAKE") != "true",
    "Enable real DuckLake integration"
  )
  root <- file.path(withr::local_tempdir(), "lake")
  layers <- c("raw", "staging", "core", "marts")
  lake <- setup_lake(path = root, backend = "ducklake", layers = layers)
  first <- publish(
    product("orders", data.frame(amount = 350)),
    to = lake,
    layer = "core"
  )
  close_lake(lake)
  lake <- open_lake(root)
  expect_identical(lake$config$backend, "ducklake")
  expect_identical(lake$config$layers, layers)
  expect_identical(
    DBI::dbGetQuery(
      lake$con,
      "SELECT type FROM duckdb_databases() WHERE database_name = 'lake'"
    )$type,
    "ducklake"
  )
  second <- publish(
    product("orders", data.frame(amount = 380)),
    to = lake,
    layer = "core"
  )
  expect_identical(second$status, "published")
  expect_equal(read_release(lake, "orders", first$release_id)$amount, 350)
  close_lake(lake)
  lake <- open_lake(root, read_only = TRUE)
  expect_equal(read_release(lake, "orders")$amount, 380)
  close_lake(lake)
})
