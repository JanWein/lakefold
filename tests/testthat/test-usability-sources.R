test_that("deliveries retain meaningful names and original definitions", {
  orders <- tw_product(
    "orders",
    data.frame(amount = 10),
    source_name = "delivery"
  ) |>
    tw_add_transform(~ transform(.x, amount = amount * 2)) |>
    tw_add_quality(~ amount > 0)
  expect_named(tw_product("orders", data.frame(id = 1))$sources, "orders")
  expect_named(tw_product("summary", orders)$sources, "orders")
  expect_equal(
    tw_collect(tw_run(orders, data = data.frame(amount = 20)))$amount,
    40
  )
  expect_equal(tw_collect(tw_run(orders))$amount, 20)
  expect_named(orders$sources, "delivery")
  rejected <- tw_run(
    orders,
    data = data.frame(amount = -1),
    stop_on_failure = FALSE
  )
  expect_identical(rejected$status, "blocked")
  expect_equal(
    tw_collect(tw_run(
      tw_product("x", data.frame(id = 1)),
      sources = list(x = data.frame(id = 2))
    ))$id,
    2
  )
})

test_that("shared graph corrections read one source and preserve upstream gates", {
  reads <- 0L
  rates <- tw_product("rates", data.frame(id = 1L, rate = 1)) |>
    tw_add_quality(~ rate > 0)
  left <- tw_product("left", data.frame(id = 1L)) |>
    tw_add_lookup(rates, by = "id")
  right <- tw_product("right", rates)
  report <- tw_product("report") |>
    tw_add_source(left) |>
    tw_add_source(right) |>
    tw_add_transform(~ .x$left)
  fresh <- function() {
    reads <<- reads + 1L
    data.frame(id = 1L, rate = 2)
  }
  result <- tw_run(report, sources = list(rates = fresh))
  expect_equal(tw_collect(result)$rate, 2)
  expect_equal(reads, 1L)
  expect_equal(tw_collect(tw_run(report))$rate, 1)
  blocked <- tw_run(
    right,
    data = data.frame(id = 1L, rate = -1),
    stop_on_failure = FALSE
  )
  expect_identical(tw_status(blocked)$success, FALSE)
})

test_that("correction mistakes fail before any reader or writer", {
  reads <- 0L
  orders <- tw_product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  })
  unknown <- tryCatch(
    tw_run(orders, sources = list(typo = data.frame(id = 2L))),
    error = identity
  )
  expect_match(
    conditionMessage(unknown),
    "Available names: orders",
    fixed = TRUE
  )
  both <- tryCatch(
    tw_run(
      orders,
      data = data.frame(id = 2L),
      sources = list(orders = data.frame(id = 3L))
    ),
    error = identity
  )
  expect_match(conditionMessage(both), "not both", fixed = TRUE)
  destination <- file.path(withr::local_tempdir(), "unopened")
  unknown <- tryCatch(
    tw_publish(
      orders,
      to = destination,
      sources = list(typo = data.frame(id = 2L))
    ),
    error = identity
  )
  expect_match(
    conditionMessage(unknown),
    "Available names: orders",
    fixed = TRUE
  )
  expect_identical(reads, 0L)
  expect_identical(dir.exists(destination), FALSE)
})

test_that("stored destinations apply only to a root and can be overridden", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  child_path <- file.path(root, "child")
  parent_path <- file.path(root, "parent")
  child <- tw_product(
    "orders",
    data.frame(amount = 10),
    execution = tw_execution_config(to = child_path)
  )
  parent <- tw_product(
    "summary",
    child,
    execution = tw_execution_config(to = parent_path)
  )
  first <- tw_publish(parent)
  expect_identical(first$status, "published")
  expect_identical(dir.exists(child_path), FALSE)
  second <- tw_publish(parent, data = data.frame(amount = 20))
  expect_equal(tw_collect(first)$amount, 10)
  expect_equal(tw_collect(second)$amount, 20)
  expect_equal(
    tw_collect(tw_run(parent, execution = tw_execution_config()))$amount,
    10
  )
  expect_identical(dir.exists(child_path), FALSE)
  expect_identical(tw_run(child)$status, "published")
})

test_that("ingestion uses a stored connection-free destination", {
  skip_if_not_installed("duckdb")
  root <- file.path(withr::local_tempdir(), "raw")
  orders <- tw_product(
    "orders",
    data.frame(amount = 10),
    execution = tw_execution_config(to = root)
  )
  accepted <- tw_ingest(orders)
  expect_identical(accepted$outputs$schema, "raw")
  expect_equal(tw_collect(accepted)$amount, 10)
  lake <- tw_open_lake(root)
  withr::defer(tw_close_lake(lake))
  error <- tryCatch(
    tw_product("orders", execution = tw_execution_config(to = lake)),
    error = identity
  )
  expect_match(
    conditionMessage(error),
    "cannot contain an open connection",
    fixed = TRUE
  )
})

test_that("targets embeds resolved defaults without activating child destinations", {
  skip_if_not_installed("targets")
  path <- file.path(withr::local_tempdir(), "unused")
  child <- tw_product(
    "orders",
    data.frame(id = 1L),
    execution = tw_execution_config(to = path)
  )
  parent <- tw_product("summary", child)
  graph <- tw_as_targets(parent)
  root_command <- graph[[2L]]$command$expr[[1L]]
  child_command <- graph[[1L]]$command$expr[[1L]]
  expect_null(attr(child_command[[2L]], "tw_execution_config"))
  expect_null(child_command[[2L]]$target)
  expect_equal(tw_collect(eval(child_command))$id, 1L)
  expect_identical(dir.exists(path), FALSE)
  configured <- tw_product(
    "summary",
    child,
    execution = tw_execution_config(to = path)
  )
  changed_command <- tw_as_targets(configured)[[2L]]$command$expr[[1L]]
  expect_identical(identical(root_command, changed_command), FALSE)
  expect_s3_class(changed_command[[2L]]$target, "tw_lake_target")
})

test_that("managed dbt correction validation runs before commands", {
  calls <- 0L
  local_mocked_bindings(tw_dbt_build = function(project, ...) {
    calls <<- calls + 1L
    project
  })
  root <- withr::local_tempdir()
  config <- tw_lake_config(path = file.path(root, "lake"))
  accepted <- run_result("run-1", "published", "release-1")
  accepted$asset <- "orders"
  accepted$output_config <- config
  corrected <- accepted
  corrected$release_id <- "release-2"
  project <- tw_dbt_project(
    file.path(root, "project"),
    lake = config,
    sources = list(orders = accepted)
  )
  result <- tw_run(project, sources = list(orders = corrected))
  expect_identical(result$source_groups[[1L]]$orders$release_id, "release-2")
  expect_identical(project$source_groups[[1L]]$orders$release_id, "release-1")
  error <- tryCatch(
    tw_run(project, sources = list(typo = corrected)),
    error = identity
  )
  expect_match(conditionMessage(error), "Available names:", fixed = TRUE)
  expect_identical(calls, 1L)
})

test_that("new deliveries retain every gate in a nested primary chain", {
  raw <- tw_product("raw", data.frame(amount = 2)) |>
    tw_add_quality(~ amount > 0)
  prepared <- tw_product("prepared", raw) |>
    tw_add_transform(~ transform(.x, amount = abs(amount)))
  report <- tw_product("report", prepared)
  original <- report
  bad <- data.frame(amount = -2)
  expect_identical(
    tw_run(report, data = bad, stop_on_failure = FALSE)$status,
    "error"
  )
  expect_identical(
    tw_run(
      report,
      sources = list(prepared = bad),
      stop_on_failure = FALSE
    )$status,
    "error"
  )
  aliased <- tw_product("report", prepared, source_name = "delivery")
  expect_identical(
    tw_run(
      aliased,
      sources = list(delivery = bad),
      stop_on_failure = FALSE
    )$status,
    "error"
  )
  expect_identical(report, original)
  expect_equal(tw_collect(tw_run(report))$amount, 2)
  expect_equal(
    tw_collect(tw_run(report, data = data.frame(amount = 3)))$amount,
    3
  )
  branches <- tw_product("branches") |>
    tw_add_source(raw) |>
    tw_add_source(raw, name = "other")
  ambiguous <- tw_product("report", tw_product("prepared", branches))
  error <- tryCatch(tw_run(ambiguous, data = bad), error = identity)
  expect_match(
    conditionMessage(error),
    "exactly one primary source at `branches`",
    fixed = TRUE
  )
})


test_that("a delivery updates shared leaf products across primary and lookup paths", {
  writes <- 0L
  local_mocked_bindings(tw_write_target.NULL = function(...) {
    writes <<- writes + 1L
    list(type = "memory")
  })
  raw <- tw_product("raw", data.frame(id = 1L, amount = 2)) |>
    tw_add_quality(~ amount > 0)
  prepared <- tw_product("prepared", raw) |> dplyr::select(id)
  shared <- tw_product("shared", prepared) |> tw_add_lookup(raw, by = "id")
  original <- shared
  result <- tw_run(shared, data = data.frame(id = 1L, amount = 3))
  expect_equal(tw_collect(result)$amount, 3)
  expect_identical(shared, original)
  writes <- 0L
  failed <- tw_run(
    shared,
    data = data.frame(id = 1L, amount = -3),
    stop_on_failure = FALSE
  )
  expect_identical(tw_status(failed)$success, FALSE)
  expect_identical(writes, 0L)
  expect_null(failed$outputs)
  expect_equal(tw_collect(tw_run(shared))$amount, 2)
})

test_that("printing and explaining a stored destination describe root writes", {
  path <- file.path(withr::local_tempdir(), "unopened")
  x <- tw_product(
    "orders",
    data.frame(id = 1L),
    execution = tw_execution_config(to = path, layer = "staging")
  )
  printed <- capture.output(print(x))
  explained <- capture.output(tw_explain(x))
  expect_match(
    paste(printed, collapse = "\n"),
    "Target: local lake (staging)",
    fixed = TRUE
  )
  expect_match(
    paste(printed, collapse = "\n"),
    "Stored execution (root only): quality = native",
    fixed = TRUE
  )
  expect_match(
    paste(explained, collapse = "\n"),
    "Publish: local lake",
    fixed = TRUE
  )
  expect_identical(dir.exists(path), FALSE)
  parent <- tw_product("summary", x)
  expect_match(
    paste(capture.output(tw_explain(parent)), collapse = "\n"),
    "Return: checked data",
    fixed = TRUE
  )
  expect_null(parent$target)
})
