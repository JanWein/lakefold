test_that("configuration and plans do not perform IO", {
  root <- tempfile("dataloom-config-")
  config <- lake_config(
    registry_duckdb(file.path(root, "meta.duckdb")),
    storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  expect_false(dir.exists(root))
  pipeline <- tw_pipeline("demo.import", config = config, code_version = "v1")
  expect_false(attr(plan(pipeline), "complete"))
  expect_output(print(pipeline), "Incomplete")
  expect_false(dir.exists(root))
  expect_error(run(pipeline), class = "tw_pipeline_invalid")
  expect_false(dir.exists(root))
})

test_that("transforms are ordered, validated and cannot change old releases", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  old <- run(f$pipeline, f$lake)
  p <- tw_pipeline("demo.transform", f$lake, code_version = "v2") |>
    tw_step_land(f$pipeline$steps$land) |>
    tw_step_extract() |>
    tw_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve + 10),
      "add"
    ) |>
    tw_step_transform(
      function(data) dplyr::mutate(data, reserve = reserve * 2),
      "scale"
    ) |>
    tw_step_validate(f$contract) |>
    tw_step_publish("risk.validated")
  plan <- plan(p)
  expect_true(attr(plan, "complete"))
  expect_equal(
    plan$step,
    c("land", "extract", "transform", "transform", "validate", "publish")
  )
  expect_equal(plan$id[3:4], c("add", "scale"))
  result <- p |> tw_execute(lake = f$lake)
  expect_equal(result$status, "published")
  expect_equal(
    sum(dplyr::collect(tbl(f$lake, "risk.validated"))$reserve),
    640
  )
  expect_equal(
    sum(
      dplyr::collect(tbl(f$lake, "risk.validated", old$release_id))$reserve
    ),
    300
  )
  expect_equal(tw_execute(p, f$lake)$status, "cached")
  p$steps$transform[[2]]$transform <- function(data) {
    dplyr::mutate(data, reserve = -1)
  }
  p$version <- "2.0.0"
  p$code_version <- "v3"
  blocked <- tw_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  expect_equal(
    sum(dplyr::collect(tbl(f$lake, "risk.validated"))$reserve),
    640
  )
})

test_that("invalid and misplaced transformations fail clearly", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  expect_error(
    tw_step_transform(f$pipeline, identity, "late"),
    class = "tw_pipeline_invalid"
  )
  p <- tw_pipeline("demo.transform", f$lake, code_version = "v1")
  expect_error(tw_step_extract(p), class = "tw_pipeline_invalid")
  p <- p |>
    tw_step_land(f$pipeline$steps$land) |>
    tw_step_extract() |>
    tw_step_transform(function(data) "wrong type", "bad")
  expect_error(tw_step_transform(p, identity, "bad"), "unique")
  p <- p |> tw_step_validate(f$contract) |> tw_step_publish("risk.validated")
  out <- tw_execute(p, f$lake, stop_on_failure = FALSE)
  expect_equal(out$status, "error")
  expect_s3_class(out$error, "tw_transform_failed")
  expect_equal(nrow(registry(f$lake, "releases")), 0)
})

test_that("object-first execution manages only connections it owns", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  tw_execute(f$pipeline, f$lake)
  product <- product(
    "demo.product",
    contract = f$contract,
    code_version = "v1"
  ) |>
    add_source(source_release(f$lake, "risk.validated"))
  expect_equal(run(product, f$lake)$status, "published")
  metric <- reserve_metric("demo.product")
  expect_equal(tw_execute(metric, f$lake)$value, 300)
  expect_true(DBI::dbIsValid(f$lake$con))
  config <- f$lake$config
  disconnect_lake(f$lake)
  expect_equal(tw_execute(metric, config)$value, 300)
  # Opening again proves the internally owned connection was released.
  lake <- connect_lake(config)
  on.exit(disconnect_lake(lake), add = TRUE)
  expect_equal(measure(lake, metric)$value, 300)
  expect_error(run(product), "connected tw_lake")
})

test_that("empty custom metrics cannot be frozen in reports", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  run(f$pipeline, f$lake)
  metric <- metric(
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
  expect_error(measure(f$lake, metric), class = "tw_metric_empty")
})
