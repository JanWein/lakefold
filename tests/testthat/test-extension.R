test_that("external packages can substitute every component without changing the workflow", {
  local_adapter_method(
    "read_source",
    "example_source",
    function(source, ...) source$data
  )
  local_adapter_method(
    "check_component",
    "example_source",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "execute_transform",
    "example_transform",
    function(transform, data, ...) {
      data$amount <- data$amount * transform$factor
      data
    }
  )
  local_adapter_method(
    "check_component",
    "example_transform",
    function(x, ...) invisible(x)
  )
  written <- NULL
  local_adapter_method(
    "write_target",
    "example_target",
    function(target, data, context, ...) {
      written <<- list(data = data, context = context)
      list(table = context$product, backend = "example")
    }
  )
  local_adapter_method(
    "check_component",
    "example_target",
    function(x, ...) invisible(x)
  )
  data <- data.frame(amount = c(10, 20))
  workflow <- function(source, transform, target = NULL) {
    product("orders") |>
      add_source(source) |>
      add_transform(transform) |>
      add_quality(~ amount > 0) |>
      set_target(target)
  }
  native <- workflow(data, function(data) transform(data, amount = amount * 2))
  custom <- workflow(
    structure(list(data = data), class = "example_source"),
    structure(list(factor = 2), class = "example_transform"),
    structure(list(), class = "example_target")
  )
  a <- run(native)
  b <- run(custom)
  expect_equal(collect(a), collect(b))
  expect_equal(written$data$amount, c(20, 40))
  expect_equal(written$context$metadata$rows, 2L)
  expect_equal(b$outputs$backend, "example")
  written <- NULL
  bad <- custom |> add_quality(~ amount < 0, "impossible")
  expect_equal(run(bad, stop_on_failure = FALSE)$status, "blocked")
  expect_null(written)
})

test_that("unsupported or invalid adapters fail before invoking source callbacks", {
  calls <- 0
  product <- product("orders") |>
    add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    set_target(structure(list(), class = "unknown_target"))
  expect_snapshot(error = TRUE, validate(product))
  expect_equal(calls, 0)
})
