test_that("quality engines change implementation without changing the predicate", {
  spec <- tw_quality_rule("positive", ~ amount > 0)
  pointblank <- tw_set_engine(spec, "pointblank")
  native <- tw_set_engine(pointblank, "native")
  expect_identical(pointblank$check, spec$check)
  expect_identical(pointblank$engine, "pointblank")
  expect_identical(spec$engine, "r")
  expect_equal(
    tw_run_quality(native, data.frame(amount = c(1, -1)))$n_failed,
    1
  )
})

test_that("reusable lookup specs retain dependency resolution", {
  lookup <- tw_lookup_spec(
    data.frame(id = 1:2, label = c("a", "b")),
    by = "id",
    name = "labels"
  )
  alternate <- tw_set_engine(lookup, "dm")
  expect_identical(alternate$by, lookup$by)
  expect_identical(lookup$engine, "native")
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders")) |>
    tw_add_recipe(tw_recipe() |> tw_step_transform(lookup))
  expect_equal(
    tw_collect(tw_trial(flow, data = data.frame(id = 1:2)))$label,
    c("a", "b")
  )
})

test_that("engine selection rejects unsupported options", {
  expect_snapshot(
    error = TRUE,
    tw_quality_rule("positive", ~ amount > 0) |> tw_set_engine("spark")
  )
})
test_that("function checks cannot silently become pointblank builders", {
  expect_snapshot(
    error = TRUE,
    tw_quality_rule("positive", function(data) all(data$amount > 0)) |>
      tw_set_engine("pointblank")
  )
})

test_that("supported quality engines agree on failure counts", {
  skip_if_not_installed("pointblank")
  spec <- tw_quality_rule("positive", ~ amount > 0)
  data <- data.frame(amount = c(1, -1, NA))
  native <- tw_run_quality(tw_set_engine(spec, "native"), data)
  alternative <- tw_run_quality(tw_set_engine(spec, "pointblank"), data)
  expect_equal(alternative$n_failed, native$n_failed)
  expect_equal(alternative$status, native$status)
})

test_that("specification printing shows engines without reading references", {
  lookup <- tw_lookup_spec(
    function() stop("must not read"),
    by = "id",
    name = "reference"
  )
  expect_output(print(lookup), "Engine: native")
  expect_output(
    print(tw_quality_rule("positive", ~ amount > 0)),
    "Engine: native"
  )
})
