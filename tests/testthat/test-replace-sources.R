test_that("corrections update shared product references and lookup inputs lazily", {
  calls <- 0L
  old <- product("rates", function() stop("old source ran"))
  left <- product("left", data.frame(id = 1L)) |> add_lookup(old, by = "id")
  right <- product("right", old)
  root <- product("root") |> add_source(left) |> add_source(right)
  fresh <- product("rates", function() {
    calls <<- calls + 1L
    data.frame(id = 1L, rate = 2)
  })
  corrected <- replace_sources(root, rates = fresh)
  expect_equal(calls, 0L)
  expect_identical(root$sources$right$sources$rates, old)
  expect_identical(corrected$sources$right$sources$rates, fresh)
  lookup <- product_sources(corrected$sources$left)
  expect_identical(lookup[[2]], fresh)
  corrected <- corrected |> add_transform(function(data) data$left)
  expect_equal(collect(run(corrected))$rate, 2)
  expect_equal(calls, 1L)
})

test_that("root slots explicitly replace results while other pinned inputs persist", {
  accepted <- run(product("orders", data.frame(id = 1L)))
  newer <- run(product("orders", data.frame(id = 2L)))
  root <- product("root") |>
    add_source(accepted, name = "current") |>
    add_source(accepted, name = "historical")
  changed <- replace_sources(root, current = newer)
  expect_identical(changed$sources$historical, root$sources$historical)
  expect_equal(read_source(changed$sources$current)$id, 2L)
  expect_snapshot(error = TRUE, replace_sources(root, orders = newer))
})

test_that("invalid and overlapping source selectors fail before execution", {
  leaf <- product("leaf", data.frame(id = 1L))
  branch <- product("branch", leaf)
  root <- product("root", branch)
  expect_snapshot(error = TRUE, replace_sources(root, missing = leaf))
  expect_snapshot(error = TRUE, replace_sources(root, leaf = leaf, leaf = leaf))
  expect_snapshot(error = TRUE, replace_sources(root, leaf))
  expect_snapshot(
    error = TRUE,
    replace_sources(
      root,
      branch = product("branch", data.frame(id = 1L)),
      leaf = leaf
    )
  )
  ambiguous <- root |> add_source(data.frame(id = 1L), name = "leaf")
  expect_snapshot(error = TRUE, replace_sources(ambiguous, leaf = leaf))
  cyclic <- branch
  cyclic$sources <- list(root = root)
  expect_snapshot(error = TRUE, replace_sources(root, branch = cyclic))
  conflict <- product("root") |>
    add_source(branch) |>
    add_source(product("leaf", data.frame(id = 2L)), name = "other")
  expect_snapshot(error = TRUE, replace_sources(conflict, branch = branch))
})

test_that("managed dbt bindings change without reading a database or writing files", {
  root <- withr::local_tempdir()
  config <- lake_config(
    registry_duckdb(file.path(root, "lake.db")),
    storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  result <- run_result("run-1", "published", "release-1")
  result$asset <- "orders"
  result$output_config <- config
  corrected <- result
  corrected$run_id <- "run-2"
  corrected$release_id <- "release-2"
  project <- dbt_project(
    file.path(root, "absent"),
    lake = config,
    sources = list(orders = result, customers = result)
  )
  changed <- replace_sources(project, orders = corrected)
  expect_equal(changed$source_groups$inputs$orders$release_id, "release-2")
  expect_identical(
    changed$source_groups$inputs$customers,
    project$source_groups$inputs$customers
  )
  expect_equal(list.files(root), character())
  project <- dbt_sources(project, list(orders = result), name = "historical")
  expect_snapshot(error = TRUE, replace_sources(project, orders = corrected))
  changed <- replace_sources(project, inputs.orders = corrected)
  expect_equal(changed$source_groups$historical$orders$release_id, "release-1")
  expect_snapshot(
    error = TRUE,
    replace_sources(
      project,
      inputs.orders = corrected,
      historical.orders = NULL
    )
  )
  expect_snapshot(error = TRUE, replace_sources(changed, unknown = corrected))
})

test_that("corrected definitions reuse existing targets caching", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  script <- function(amount) {
    writeLines(
      c(
        "library(tidyweave)",
        "orders_definition <- product('orders', data.frame(amount = 1))",
        "total_definition <- product('total', orders_definition)",
        paste0(
          "fresh_definition <- product('orders', data.frame(amount = ",
          amount,
          "))"
        ),
        "total_definition <- replace_sources(total_definition, orders = fresh_definition)",
        "unrelated_definition <- product('unrelated', data.frame(id = 1L))",
        "as_targets(list(total_definition, unrelated_definition), evidence = 'evidence')"
      ),
      "_targets.R"
    )
  }
  script(2)
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(nrow(run_history("evidence")), 3L)
  unrelated_run <- targets::tar_read(unrelated)$run_id
  script(3)
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(collect(targets::tar_read(total))$amount, 3)
  expect_equal(nrow(run_history("evidence")), 5L)
  expect_equal(targets::tar_read(unrelated)$run_id, unrelated_run)
})

test_that("correcting a product input retains its transformations and quality gates", {
  orders <- product("orders", data.frame(amount = 1)) |>
    dplyr::mutate(amount = amount * 2) |>
    add_quality(~ amount > 0)
  totals <- product("totals", orders)
  corrected <- replace_sources(totals, orders = data.frame(amount = 3))
  expect_equal(collect(run(corrected))$amount, 6)
  failed <- replace_sources(totals, orders = data.frame(amount = -3))
  upstream <- run(failed$sources$orders, stop_on_failure = FALSE)
  expect_equal(upstream$status, "blocked")
  expect_equal(run(failed, stop_on_failure = FALSE)$status, "error")
  multiple <- product("multiple") |>
    add_source(orders) |>
    add_source(data.frame(id = 1L), name = "other")
  expect_snapshot(
    error = TRUE,
    replace_sources(product("root", multiple), multiple = data.frame(id = 2L))
  )
})

test_that("corrections retain exact immutable references in unselected slots", {
  root <- withr::local_tempdir()
  config <- lake_config(
    registry_duckdb(file.path(root, "lake.db")),
    storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  old <- run_result("run-1", "published", "release-1")
  old$asset <- "orders"
  old$output_config <- config
  fresh <- old
  fresh$run_id <- "run-2"
  fresh$release_id <- "release-2"
  definition <- product("report") |>
    add_source(old, name = "current") |>
    add_source(old, name = "historical")
  corrected <- replace_sources(definition, current = fresh)
  expect_identical(corrected$sources$historical, definition$sources$historical)
  expect_equal(corrected$sources$current$release_id, "release-2")
  expect_equal(list.files(root), character())
})
