test_that("configuration and plans do not perform IO", {
  root <- tempfile("dataloom-config-")
  config <- dl_config(
    dl_catalog_duckdb(file.path(root, "meta.duckdb")),
    dl_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  expect_false(dir.exists(root))
  pipeline <- dl_pipeline("demo.import", config = config, code_version = "v1")
  expect_false(attr(dl_plan(pipeline), "complete"))
  expect_output(print(pipeline), "Incomplete")
  expect_false(dir.exists(root))
  expect_error(dl_run(pipeline), class = "dl_pipeline_invalid")
  expect_false(dir.exists(root))
})

test_that("transforms are ordered, validated and cannot change old releases", {
  f <- fixture()
  on.exit(cleanup(f))
  old <- dl_run(f$pipeline, f$lake)
  p <- dl_pipeline("demo.transform", f$lake, code_version = "v2") |>
    dl_step_land(f$pipeline$steps$land) |>
    dl_step_extract() |>
    dl_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve + 10),
      "add"
    ) |>
    dl_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve * 2),
      "scale"
    ) |>
    dl_step_validate(f$contract) |>
    dl_step_publish("risk.validated")
  plan <- dl_plan(p)
  expect_true(attr(plan, "complete"))
  expect_equal(
    plan$step,
    c("land", "extract", "transform", "transform", "validate", "publish")
  )
  expect_equal(plan$id[3:4], c("add", "scale"))
  result <- p |> dl_execute(lake = f$lake)
  expect_equal(result$status, "published")
  expect_equal(
    sum(dplyr::collect(dl_tbl(f$lake, "risk.validated"))$reserve),
    640
  )
  expect_equal(
    sum(
      dplyr::collect(dl_tbl(f$lake, "risk.validated", old$release_id))$reserve
    ),
    300
  )
  expect_equal(dl_execute(p, f$lake)$status, "cached")
  p$steps$transform[[2]]$transform <- function(data) {
    dplyr::mutate(data, reserve = -1)
  }
  p$version <- "2.0.0"
  p$code_version <- "v3"
  blocked <- dl_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(
    sum(dplyr::collect(dl_tbl(f$lake, "risk.validated"))$reserve),
    640
  )
})

test_that("invalid and misplaced transformations fail clearly", {
  f <- fixture()
  on.exit(cleanup(f))
  expect_error(
    dl_step_transform(f$pipeline, identity, "late"),
    class = "dl_pipeline_invalid"
  )
  p <- dl_pipeline("demo.transform", f$lake, code_version = "v1")
  expect_error(dl_step_extract(p), class = "dl_pipeline_invalid")
  p <- p |>
    dl_step_land(f$pipeline$steps$land) |>
    dl_step_extract() |>
    dl_step_transform(function(data) "wrong type", "bad")
  expect_error(dl_step_transform(p, identity, "bad"), "unique")
  p <- p |> dl_step_validate(f$contract) |> dl_step_publish("risk.validated")
  out <- dl_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(out$status, "error")
  expect_s3_class(out$error, "dl_transform_failed")
  expect_equal(nrow(dl_registry(f$lake, "releases")), 0)
})

test_that("object-first execution manages only connections it owns", {
  f <- fixture()
  on.exit(cleanup(f))
  dl_execute(f$pipeline, f$lake)
  product <- dl_product(
    "demo.product",
    c(source = "risk.validated"),
    function(inputs) inputs$source,
    f$contract,
    code_version = "v1"
  )
  expect_equal(dl_execute(product, f$lake)$status, "published")
  metric <- reserve_metric("demo.product")
  expect_equal(dl_execute(metric, f$lake)$value, 300)
  expect_true(DBI::dbIsValid(f$lake$con))
  config <- f$lake$config
  dl_disconnect(f$lake)
  expect_equal(dl_execute(metric, config)$value, 300)
  # Opening again proves the internally owned connection was released.
  lake <- dl_connect(config)
  on.exit(dl_disconnect(lake), add = TRUE)
  expect_equal(dl_measure(lake, metric)$value, 300)
  expect_error(dl_execute(product), "connected dl_lake")
})

test_that("empty custom metrics cannot be frozen in reports", {
  f <- fixture()
  on.exit(cleanup(f))
  dl_run(f$pipeline, f$lake)
  metric <- dl_metric(
    "demo.empty",
    "risk.validated",
    compute = function(data, dimensions, params) {
      data.frame(value = numeric())
    },
    time_behavior = "flow",
    unit = "EUR",
    owner = "Risk",
    description = "Empty result",
    approved = TRUE,
    code_version = "v1"
  )
  expect_error(dl_measure(f$lake, metric), class = "dl_metric_empty")
})
