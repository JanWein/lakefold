test_that("configuration and plans do not perform IO", {
  root <- tempfile("dataloom-config-")
  config <- dr_lake_config(
    dr_registry_duckdb(file.path(root, "meta.duckdb")),
    dr_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  expect_false(dir.exists(root))
  pipeline <- dr_pipeline("demo.import", config = config, code_version = "v1")
  expect_false(attr(dr_plan(pipeline), "complete"))
  expect_output(print(pipeline), "Incomplete")
  expect_false(dir.exists(root))
  expect_error(dr_run(pipeline), class = "dr_pipeline_invalid")
  expect_false(dir.exists(root))
})

test_that("transforms are ordered, validated and cannot change old releases", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  old <- dr_run(f$pipeline, f$lake)
  p <- dr_pipeline("demo.transform", f$lake, code_version = "v2") |>
    dr_step_land(f$pipeline$steps$land) |>
    dr_step_extract() |>
    pipeline_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve + 10),
      "add"
    ) |>
    pipeline_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve * 2),
      "scale"
    ) |>
    dr_step_validate(f$contract) |>
    dr_step_publish("risk.validated")
  plan <- dr_plan(p)
  expect_true(attr(plan, "complete"))
  expect_equal(
    plan$step,
    c("land", "extract", "transform", "transform", "validate", "publish")
  )
  expect_equal(plan$id[3:4], c("add", "scale"))
  result <- p |> dr_execute(lake = f$lake)
  expect_equal(result$status, "published")
  expect_equal(
    sum(dplyr::collect(dr_tbl(f$lake, "risk.validated"))$reserve),
    640
  )
  expect_equal(
    sum(
      dplyr::collect(dr_tbl(f$lake, "risk.validated", old$release_id))$reserve
    ),
    300
  )
  expect_equal(dr_execute(p, f$lake)$status, "cached")
  p$steps$transform[[2]]$transform <- function(data) {
    dplyr::mutate(data, reserve = -1)
  }
  p$version <- "2.0.0"
  p$code_version <- "v3"
  blocked <- dr_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(
    sum(dplyr::collect(dr_tbl(f$lake, "risk.validated"))$reserve),
    640
  )
})

test_that("invalid and misplaced transformations fail clearly", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  expect_error(
    pipeline_step_transform(f$pipeline, identity, "late"),
    class = "dr_pipeline_invalid"
  )
  p <- dr_pipeline("demo.transform", f$lake, code_version = "v1")
  expect_error(dr_step_extract(p), class = "dr_pipeline_invalid")
  p <- p |>
    dr_step_land(f$pipeline$steps$land) |>
    dr_step_extract() |>
    pipeline_step_transform(function(data) "wrong type", "bad")
  expect_error(pipeline_step_transform(p, identity, "bad"), "unique")
  p <- p |> dr_step_validate(f$contract) |> dr_step_publish("risk.validated")
  out <- dr_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(out$status, "error")
  expect_s3_class(out$error, "dr_transform_failed")
  expect_equal(nrow(dr_registry(f$lake, "releases")), 0)
})

test_that("object-first execution manages only connections it owns", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_execute(f$pipeline, f$lake)
  product <- dr_product(
    "demo.product",
    contract = f$contract,
    code_version = "v1"
  ) |>
    dr_add_source(dr_source_release(f$lake, "risk.validated"))
  expect_equal(dr_run(product, f$lake)$status, "published")
  metric <- reserve_metric("demo.product")
  expect_equal(dr_execute(metric, f$lake)$value, 300)
  expect_true(DBI::dbIsValid(f$lake$con))
  config <- f$lake$config
  dr_disconnect_lake(f$lake)
  expect_equal(dr_execute(metric, config)$value, 300)
  # Opening again proves the internally owned connection was released.
  lake <- dr_connect_lake(config)
  on.exit(dr_disconnect_lake(lake), add = TRUE)
  expect_equal(dr_measure(lake, metric)$value, 300)
  expect_error(dr_run(product), "connected dr_lake")
})

test_that("empty custom metrics cannot be frozen in reports", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  metric <- dr_metric(
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
  expect_error(dr_measure(f$lake, metric), class = "dr_metric_empty")
})
