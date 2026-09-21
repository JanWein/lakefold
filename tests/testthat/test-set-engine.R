test_that("quality engines change implementation without changing the predicate", {
  spec <- quality_rule("positive", ~ amount > 0)
  pointblank <- set_engine(spec, "pointblank")
  native <- set_engine(pointblank, "native")
  expect_identical(pointblank$check, spec$check)
  expect_identical(pointblank$engine, "pointblank")
  expect_identical(spec$engine, "r")
  expect_equal(run_quality(native, data.frame(amount = c(1, -1)))$n_failed, 1)
})

test_that("reusable lookup specs retain dependency resolution", {
  lookup <- lookup_spec(
    data.frame(id = 1:2, label = c("a", "b")),
    by = "id",
    name = "labels"
  )
  alternate <- set_engine(lookup, "dm")
  expect_identical(alternate$by, lookup$by)
  expect_identical(lookup$engine, "native")
  flow <- workflow() |>
    add_product(product("orders")) |>
    add_recipe(recipe() |> step_transform(lookup))
  expect_equal(
    collect(trial(flow, data = data.frame(id = 1:2)))$label,
    c("a", "b")
  )
})

test_that("engine selection rejects unsupported options", {
  expect_snapshot(
    error = TRUE,
    quality_rule("positive", ~ amount > 0) |> set_engine("spark")
  )
})
test_that("function checks cannot silently become pointblank builders", {
  expect_snapshot(
    error = TRUE,
    quality_rule("positive", function(data) all(data$amount > 0)) |>
      set_engine("pointblank")
  )
})

test_that("supported quality engines agree on failure counts", {
  skip_if_not_installed("pointblank")
  spec <- quality_rule("positive", ~ amount > 0)
  data <- data.frame(amount = c(1, -1, NA))
  native <- run_quality(set_engine(spec, "native"), data)
  alternative <- run_quality(set_engine(spec, "pointblank"), data)
  expect_equal(alternative$n_failed, native$n_failed)
  expect_equal(alternative$status, native$status)
})

test_that("specification printing shows engines without reading references", {
  lookup <- lookup_spec(
    function() stop("must not read"),
    by = "id",
    name = "reference"
  )
  expect_output(print(lookup), "Engine: native")
  expect_output(print(quality_rule("positive", ~ amount > 0)), "Engine: native")
})
