local_adapter_method <- function(generic, class, method, env = parent.frame()) {
  table <- get(".__S3MethodsTable__.", envir = asNamespace("lakefold"))
  name <- paste(generic, class, sep = ".")
  old <- get0(name, envir = table, inherits = FALSE)
  registerS3method(generic, class, method, envir = asNamespace("lakefold"))
  withr::defer(
    {
      if (is.null(old)) {
        rm(list = name, envir = table)
      } else {
        assign(name, old, envir = table)
      }
    },
    envir = env
  )
}

test_that("external packages can substitute every component without changing the workflow", {
  local_adapter_method(
    "dl_read_source",
    "example_source",
    function(source, ...) source$data
  )
  local_adapter_method(
    "dl_check_component",
    "example_source",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "dl_execute_transform",
    "example_transform",
    function(transform, data, ...) {
      data$amount <- data$amount * transform$factor
      data
    }
  )
  local_adapter_method(
    "dl_check_component",
    "example_transform",
    function(x, ...) invisible(x)
  )
  written <- NULL
  local_adapter_method(
    "dl_write_target",
    "example_target",
    function(target, data, context, ...) {
      written <<- list(data = data, context = context)
      list(table = context$product, backend = "example")
    }
  )
  local_adapter_method(
    "dl_check_component",
    "example_target",
    function(x, ...) invisible(x)
  )
  data <- data.frame(amount = c(10, 20))
  workflow <- function(source, transform, target = NULL) {
    dl_product("orders") |>
      dl_add_source(source) |>
      dl_add_transform(transform) |>
      dl_add_quality(~ amount > 0) |>
      dl_add_target(target)
  }
  native <- workflow(data, function(data) transform(data, amount = amount * 2))
  custom <- workflow(
    structure(list(data = data), class = "example_source"),
    structure(list(factor = 2), class = "example_transform"),
    structure(list(), class = "example_target")
  )
  a <- dl_run(native)
  b <- dl_run(custom)
  expect_equal(dl_collect(a), dl_collect(b))
  expect_equal(written$data$amount, c(20, 40))
  expect_equal(written$context$metadata$rows, 2L)
  expect_equal(b$outputs$backend, "example")
  written <- NULL
  bad <- custom |> dl_add_quality(~ amount < 0, "impossible")
  expect_equal(dl_run(bad, stop_on_failure = FALSE)$status, "blocked")
  expect_null(written)
})

test_that("unsupported or invalid adapters fail before invoking source callbacks", {
  calls <- 0
  product <- dl_product("orders") |>
    dl_add_source(function() {
      calls <<- calls + 1
      data.frame(id = 1L)
    }) |>
    dl_add_target(structure(list(), class = "unknown_target"))
  expect_snapshot(error = TRUE, dl_validate(product))
  expect_equal(calls, 0)
})
