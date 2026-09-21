test_that("Parquet sources preserve lazy Arrow execution and table types", {
  skip_if_not_installed("arrow")
  path <- withr::local_tempfile(fileext = ".parquet")
  data <- data.frame(id = 1:3, amount = c(2, 4, 6))
  output <- tw_write_target(tw_target_parquet(path), data, list())
  expect_equal(output$rows, 3L)
  lazy <- tw_read_source(tw_source_parquet(path))
  expect_s3_class(lazy, "Dataset")
  expect_true(tw_capabilities(tw_source_parquet(path))$lazy)
  expect_equal(
    tw_collect(dplyr::filter(lazy, id > 1L)),
    tibble::as_tibble(data[2:3, ])
  )
  expect_equal(
    tw_read_source(tw_source_parquet(path, lazy = FALSE)),
    tibble::as_tibble(data)
  )
  expect_identical(tw_read_source(lazy), lazy)
  expect_silent(tw_check_component(lazy))
  expect_false(grepl(
    "token",
    paste(
      tw_inspect(tw_source_parquet(
        "s3://bucket/data?token=secret"
      )),
      collapse = " "
    )
  ))
})

test_that("Parquet publication preserves the old file on write failure", {
  skip_if_not_installed("arrow")
  path <- withr::local_tempfile(fileext = ".parquet")
  original <- data.frame(id = 1L)
  tw_write_target(tw_target_parquet(path), original, list())
  before <- readBin(path, "raw", n = file.size(path))
  expect_error(tw_check_component(tw_target_parquet(path)), "already exists")
  expect_error(tw_write_target(
    tw_target_parquet(
      path,
      overwrite = TRUE,
      compression = "invalid-compressor"
    ),
    data.frame(id = 2L),
    list()
  ))
  expect_identical(readBin(path, "raw", n = file.size(path)), before)
  expect_false(tw_capabilities(tw_target_parquet(path))$transactions)
  expect_error(tw_target_parquet("s3://bucket/path.parquet"), "local path")
  expect_error(
    tw_check_component(tw_source_parquet(paste0(path, "-missing"))),
    "missing"
  )
})
