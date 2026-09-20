test_that("local shorthand defines a lake without creating anything", {
  root <- file.path(withr::local_tempdir(), "new-lake")
  config <- lake_config(path = root)
  expect_s3_class(config, "tw_config")
  expect_identical(config$backend, "duckdb")
  expect_identical(config$layers, c("raw", "validated", "products"))
  expect_identical(config$catalog$path, file.path(root, "metadata.duckdb"))
  expect_identical(config$storage$path, file.path(root, "data"))
  expect_identical(config$landing, file.path(root, "landing"))
  expect_false(dir.exists(root))
  expect_identical(lake_config()$backend, "ducklake")
  expect_identical(
    lake_config(path = root, backend = "ducklake")$backend,
    "ducklake"
  )
  expect_false(dir.exists(root))
  expect_error(
    lake_config(path = root, catalog = registry_duckdb("elsewhere.db")),
    "not both"
  )
  expect_error(
    lake_config(path = root, storage = storage_local("elsewhere")),
    "not both"
  )
  expect_error(lake_config(path = root, landing = "elsewhere"), "not both")
  expect_false(dir.exists(root))
})

test_that("local shorthand preserves saved backends and refuses unknown folders", {
  root <- withr::local_tempdir()
  writeLines("keep this", file.path(root, "important.txt"))
  expect_error(lake_config(path = root), "not empty")
  expect_identical(readLines(file.path(root, "important.txt")), "keep this")
  expect_error(
    lake_config(path = file.path(root, "important.txt")),
    "is a file"
  )
  manifest <- file.path(root, "tidyweave.json")
  writeLines('{"format":1,"backend":"ducklake"}', manifest)
  expect_identical(lake_config(path = root)$backend, "ducklake")
  expect_error(
    lake_config(path = root, backend = "duckdb"),
    "different backend"
  )
  writeLines("not json", manifest)
  expect_error(lake_config(path = root), "Invalid tidyweave.json")
})

test_that("shorthand and open_lake reconnect to the same local storage", {
  skip_if_not_installed("duckdb")
  root <- file.path(withr::local_tempdir(), "lake")
  config <- lake_config(path = root)
  expect_message(
    accepted <- ingest(data.frame(id = 1L), to = config, name = "orders"),
    NA
  )
  expect_true(file.exists(file.path(root, "tidyweave.json")))
  lake <- open_lake(root)
  expect_equal(read_release(lake, "orders", accepted$release_id)$id, 1L)
  close_lake(lake)
  manifest <- readLines(file.path(root, "tidyweave.json"))
  readonly <- lake_config(path = root, read_only = TRUE)
  lake <- connect_lake(readonly)
  expect_true(lake$config$read_only)
  expect_equal(read_release(lake, "orders", accepted$release_id)$id, 1L)
  close_lake(lake)
  expect_identical(readLines(file.path(root, "tidyweave.json")), manifest)
  other <- file.path(withr::local_tempdir(), "from-open-lake")
  lake <- open_lake(other)
  close_lake(lake)
  expect_identical(lake_config(path = other)$backend, "duckdb")
  absent <- file.path(withr::local_tempdir(), "readonly-absent")
  expect_error(
    connect_lake(lake_config(path = absent, read_only = TRUE)),
    "must already exist"
  )
  expect_false(dir.exists(absent))
})

test_that("a failed initial connection retains a retryable backend identity", {
  skip_if_not_installed("duckdb")
  root <- file.path(withr::local_tempdir(), "lake")
  config <- lake_config(path = root)
  testthat::local_mocked_bindings(
    dbConnect = function(...) stop("connection unavailable"),
    .package = "DBI"
  )
  expect_error(connect_lake(config), "connection unavailable")
  expect_true(file.exists(file.path(root, "tidyweave.json")))
  expect_identical(lake_config(path = root)$backend, "duckdb")
  expect_error(connect_lake(config), "connection unavailable")
})

test_that("driver information is quiet while warnings and connection failures survive", {
  skip_if_not_installed("duckdb")
  config <- lake_config(path = file.path(withr::local_tempdir(), "lake"))
  testthat::local_mocked_bindings(
    duckdb = function(...) {
      message("driver storage information")
      warning("driver warning", call. = FALSE)
      structure(list(), class = "mock_driver")
    },
    .package = "duckdb"
  )
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      force(drv)
      message("connection diagnostic")
      stop("connection failed", call. = FALSE)
    },
    .package = "DBI"
  )
  messages <- character()
  expect_warning(
    expect_error(
      withCallingHandlers(
        connect_lake(config),
        message = function(condition) {
          messages <<- c(messages, conditionMessage(condition))
          invokeRestart("muffleMessage")
        }
      ),
      "connection failed"
    ),
    "driver warning"
  )
  expect_identical(messages, "connection diagnostic\n")
})
