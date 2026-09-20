test_that("deliveries retain meaningful names and original definitions", {
  orders <- product(
    "orders",
    data.frame(amount = 10),
    source_name = "delivery"
  ) |>
    add_transform(~ transform(.x, amount = amount * 2)) |>
    add_quality(~ amount > 0)
  expect_named(product("orders", data.frame(id = 1))$sources, "orders")
  expect_named(product("summary", orders)$sources, "orders")
  expect_equal(collect(run(orders, data = data.frame(amount = 20)))$amount, 40)
  expect_equal(collect(run(orders))$amount, 20)
  expect_named(orders$sources, "delivery")
  rejected <- run(
    orders,
    data = data.frame(amount = -1),
    stop_on_failure = FALSE
  )
  expect_identical(rejected$status, "blocked")
  expect_equal(
    collect(run(
      product("x", data.frame(id = 1)),
      sources = list(x = data.frame(id = 2))
    ))$id,
    2
  )
})

test_that("shared graph corrections read one source and preserve upstream gates", {
  reads <- 0L
  rates <- product("rates", data.frame(id = 1L, rate = 1)) |>
    add_quality(~ rate > 0)
  left <- product("left", data.frame(id = 1L)) |> add_lookup(rates, by = "id")
  right <- product("right", rates)
  report <- product("report") |>
    add_source(left) |>
    add_source(right) |>
    add_transform(~ .x$left)
  fresh <- function() {
    reads <<- reads + 1L
    data.frame(id = 1L, rate = 2)
  }
  result <- run(report, sources = list(rates = fresh))
  expect_equal(collect(result)$rate, 2)
  expect_equal(reads, 1L)
  expect_equal(collect(run(report))$rate, 1)
  blocked <- run(
    right,
    data = data.frame(id = 1L, rate = -1),
    stop_on_failure = FALSE
  )
  expect_identical(status(blocked)$success, FALSE)
})

test_that("correction mistakes fail before any reader or writer", {
  reads <- 0L
  orders <- product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  })
  unknown <- tryCatch(
    run(orders, sources = list(typo = data.frame(id = 2L))),
    error = identity
  )
  expect_match(
    conditionMessage(unknown),
    "Available names: orders",
    fixed = TRUE
  )
  both <- tryCatch(
    run(
      orders,
      data = data.frame(id = 2L),
      sources = list(orders = data.frame(id = 3L))
    ),
    error = identity
  )
  expect_match(conditionMessage(both), "not both", fixed = TRUE)
  destination <- file.path(withr::local_tempdir(), "unopened")
  unknown <- tryCatch(
    publish(
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
  child <- product(
    "orders",
    data.frame(amount = 10),
    execution = execution_config(to = child_path)
  )
  parent <- product(
    "summary",
    child,
    execution = execution_config(to = parent_path)
  )
  first <- publish(parent)
  expect_identical(first$status, "published")
  expect_identical(dir.exists(child_path), FALSE)
  second <- publish(parent, data = data.frame(amount = 20))
  expect_equal(collect(first)$amount, 10)
  expect_equal(collect(second)$amount, 20)
  expect_equal(collect(run(parent, execution = execution_config()))$amount, 10)
  expect_identical(dir.exists(child_path), FALSE)
  expect_identical(run(child)$status, "published")
})

test_that("ingestion uses a stored connection-free destination", {
  skip_if_not_installed("duckdb")
  root <- file.path(withr::local_tempdir(), "raw")
  orders <- product(
    "orders",
    data.frame(amount = 10),
    execution = execution_config(to = root)
  )
  accepted <- ingest(orders)
  expect_identical(accepted$outputs$schema, "raw")
  expect_equal(collect(accepted)$amount, 10)
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  error <- tryCatch(
    product("orders", execution = execution_config(to = lake)),
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
  child <- product(
    "orders",
    data.frame(id = 1L),
    execution = execution_config(to = path)
  )
  parent <- product("summary", child)
  graph <- as_targets(parent)
  root_command <- graph[[2L]]$command$expr[[1L]]
  child_command <- graph[[1L]]$command$expr[[1L]]
  expect_null(attr(child_command[[2L]], "tw_execution_config"))
  expect_null(child_command[[2L]]$target)
  expect_equal(collect(eval(child_command))$id, 1L)
  expect_identical(dir.exists(path), FALSE)
  configured <- product(
    "summary",
    child,
    execution = execution_config(to = path)
  )
  changed_command <- as_targets(configured)[[2L]]$command$expr[[1L]]
  expect_identical(identical(root_command, changed_command), FALSE)
  expect_s3_class(changed_command[[2L]]$target, "tw_lake_target")
})

test_that("managed dbt correction validation runs before commands", {
  calls <- 0L
  local_mocked_bindings(dbt_build = function(project, ...) {
    calls <<- calls + 1L
    project
  })
  root <- withr::local_tempdir()
  config <- lake_config(path = file.path(root, "lake"))
  accepted <- run_result("run-1", "published", "release-1")
  accepted$asset <- "orders"
  accepted$output_config <- config
  corrected <- accepted
  corrected$release_id <- "release-2"
  project <- dbt_project(
    file.path(root, "project"),
    lake = config,
    sources = list(orders = accepted)
  )
  result <- run(project, sources = list(orders = corrected))
  expect_identical(result$source_groups[[1L]]$orders$release_id, "release-2")
  expect_identical(project$source_groups[[1L]]$orders$release_id, "release-1")
  error <- tryCatch(
    run(project, sources = list(typo = corrected)),
    error = identity
  )
  expect_match(conditionMessage(error), "Available names:", fixed = TRUE)
  expect_identical(calls, 1L)
})

test_that("new deliveries retain every gate in a nested primary chain", {
  raw <- product("raw", data.frame(amount = 2)) |> add_quality(~ amount > 0)
  prepared <- product("prepared", raw) |>
    add_transform(~ transform(.x, amount = abs(amount)))
  report <- product("report", prepared)
  original <- report
  bad <- data.frame(amount = -2)
  expect_identical(
    run(report, data = bad, stop_on_failure = FALSE)$status,
    "error"
  )
  expect_identical(
    run(report, sources = list(prepared = bad), stop_on_failure = FALSE)$status,
    "error"
  )
  aliased <- product("report", prepared, source_name = "delivery")
  expect_identical(
    run(
      aliased,
      sources = list(delivery = bad),
      stop_on_failure = FALSE
    )$status,
    "error"
  )
  expect_identical(report, original)
  expect_equal(collect(run(report))$amount, 2)
  expect_equal(collect(run(report, data = data.frame(amount = 3)))$amount, 3)
  branches <- product("branches") |>
    add_source(raw) |>
    add_source(raw, name = "other")
  ambiguous <- product("report", product("prepared", branches))
  error <- tryCatch(run(ambiguous, data = bad), error = identity)
  expect_match(
    conditionMessage(error),
    "exactly one primary source at `branches`",
    fixed = TRUE
  )
})


test_that("a delivery updates shared leaf products across primary and lookup paths", {
  writes <- 0L
  local_mocked_bindings(write_target.NULL = function(...) {
    writes <<- writes + 1L
    list(type = "memory")
  })
  raw <- product("raw", data.frame(id = 1L, amount = 2)) |>
    add_quality(~ amount > 0)
  prepared <- product("prepared", raw) |> dplyr::select(id)
  shared <- product("shared", prepared) |> add_lookup(raw, by = "id")
  original <- shared
  result <- run(shared, data = data.frame(id = 1L, amount = 3))
  expect_equal(collect(result)$amount, 3)
  expect_identical(shared, original)
  writes <- 0L
  failed <- run(
    shared,
    data = data.frame(id = 1L, amount = -3),
    stop_on_failure = FALSE
  )
  expect_identical(status(failed)$success, FALSE)
  expect_identical(writes, 0L)
  expect_null(failed$outputs)
  expect_equal(collect(run(shared))$amount, 2)
})

test_that("printing and explaining a stored destination describe root writes", {
  path <- file.path(withr::local_tempdir(), "unopened")
  x <- product(
    "orders",
    data.frame(id = 1L),
    execution = execution_config(to = path, layer = "staging")
  )
  printed <- capture.output(print(x))
  explained <- capture.output(explain(x))
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
  parent <- product("summary", x)
  expect_match(
    paste(capture.output(explain(parent)), collapse = "\n"),
    "Return: checked data",
    fixed = TRUE
  )
  expect_null(parent$target)
})
