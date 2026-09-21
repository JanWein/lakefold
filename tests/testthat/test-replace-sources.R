test_that("corrections update shared product references and lookup inputs lazily", {
  calls <- 0L
  old <- tw_product("rates", function() stop("old source ran"))
  left <- tw_product("left", data.frame(id = 1L)) |>
    tw_add_lookup(old, by = "id")
  right <- tw_product("right", old)
  root <- tw_product("root") |> tw_add_source(left) |> tw_add_source(right)
  fresh <- tw_product("rates", function() {
    calls <<- calls + 1L
    data.frame(id = 1L, rate = 2)
  })
  corrected <- tw_replace_sources(root, rates = fresh)
  expect_equal(calls, 0L)
  expect_identical(root$sources$right$sources$rates, old)
  expect_identical(corrected$sources$right$sources$rates, fresh)
  lookup <- product_sources(corrected$sources$left)
  expect_identical(lookup[[2]], fresh)
  corrected <- corrected |> tw_add_transform(function(data) data$left)
  expect_equal(tw_collect(tw_run(corrected))$rate, 2)
  expect_equal(calls, 1L)
})

test_that("root slots explicitly replace results while other pinned inputs persist", {
  accepted <- tw_run(tw_product("orders", data.frame(id = 1L)))
  newer <- tw_run(tw_product("orders", data.frame(id = 2L)))
  root <- tw_product("root") |>
    tw_add_source(accepted, name = "current") |>
    tw_add_source(accepted, name = "historical")
  changed <- tw_replace_sources(root, current = newer)
  expect_identical(changed$sources$historical, root$sources$historical)
  expect_equal(tw_read_source(changed$sources$current)$id, 2L)
  expect_snapshot(error = TRUE, tw_replace_sources(root, orders = newer))
})

test_that("invalid and overlapping source selectors fail before execution", {
  leaf <- tw_product("leaf", data.frame(id = 1L))
  branch <- tw_product("branch", leaf)
  root <- tw_product("root", branch)
  expect_snapshot(error = TRUE, tw_replace_sources(root, missing = leaf))
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(root, leaf = leaf, leaf = leaf)
  )
  expect_snapshot(error = TRUE, tw_replace_sources(root, leaf))
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(
      root,
      branch = tw_product("branch", data.frame(id = 1L)),
      leaf = leaf
    )
  )
  ambiguous <- root |> tw_add_source(data.frame(id = 1L), name = "leaf")
  expect_snapshot(error = TRUE, tw_replace_sources(ambiguous, leaf = leaf))
  cyclic <- branch
  cyclic$sources <- list(root = root)
  expect_snapshot(error = TRUE, tw_replace_sources(root, branch = cyclic))
  conflict <- tw_product("root") |>
    tw_add_source(branch) |>
    tw_add_source(tw_product("leaf", data.frame(id = 2L)), name = "other")
  expect_snapshot(error = TRUE, tw_replace_sources(conflict, branch = branch))
})

test_that("managed dbt bindings change without reading a database or writing files", {
  root <- withr::local_tempdir()
  config <- tw_lake_config(
    tw_registry_duckdb(file.path(root, "lake.db")),
    tw_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  result <- run_result("run-1", "published", "release-1")
  result$asset <- "orders"
  result$output_config <- config
  corrected <- result
  corrected$run_id <- "run-2"
  corrected$release_id <- "release-2"
  project <- tw_dbt_project(
    file.path(root, "absent"),
    lake = config,
    sources = list(orders = result, customers = result)
  )
  changed <- tw_replace_sources(project, orders = corrected)
  expect_equal(changed$source_groups$inputs$orders$release_id, "release-2")
  expect_identical(
    changed$source_groups$inputs$customers,
    project$source_groups$inputs$customers
  )
  expect_equal(list.files(root), character())
  project <- tw_dbt_sources(project, list(orders = result), name = "historical")
  expect_snapshot(error = TRUE, tw_replace_sources(project, orders = corrected))
  changed <- tw_replace_sources(project, inputs.orders = corrected)
  expect_equal(changed$source_groups$historical$orders$release_id, "release-1")
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(
      project,
      inputs.orders = corrected,
      historical.orders = NULL
    )
  )
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(changed, unknown = corrected)
  )
})

test_that("corrected definitions reuse existing targets caching", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  script <- function(amount) {
    writeLines(
      c(
        "library(tidyweave)",
        "orders_definition <- tw_product('orders', data.frame(amount = 1))",
        "total_definition <- tw_product('total', orders_definition)",
        paste0(
          "fresh_definition <- tw_product('orders', data.frame(amount = ",
          amount,
          "))"
        ),
        "total_definition <- tw_replace_sources(total_definition, orders = fresh_definition)",
        "unrelated_definition <- tw_product('unrelated', data.frame(id = 1L))",
        "tw_as_targets(list(total_definition, unrelated_definition), evidence = 'evidence')"
      ),
      "_targets.R"
    )
  }
  script(2)
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(nrow(tw_run_history("evidence")), 3L)
  unrelated_run <- targets::tar_read(unrelated)$run_id
  script(3)
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(tw_collect(targets::tar_read(total))$amount, 3)
  expect_equal(nrow(tw_run_history("evidence")), 5L)
  expect_equal(targets::tar_read(unrelated)$run_id, unrelated_run)
})

test_that("correcting a product input retains its transformations and quality gates", {
  orders <- tw_product("orders", data.frame(amount = 1)) |>
    dplyr::mutate(amount = amount * 2) |>
    tw_add_quality(~ amount > 0)
  totals <- tw_product("totals", orders)
  corrected <- tw_replace_sources(totals, orders = data.frame(amount = 3))
  expect_equal(tw_collect(tw_run(corrected))$amount, 6)
  failed <- tw_replace_sources(totals, orders = data.frame(amount = -3))
  upstream <- tw_run(failed$sources$orders, stop_on_failure = FALSE)
  expect_equal(upstream$status, "blocked")
  expect_equal(tw_run(failed, stop_on_failure = FALSE)$status, "error")
  multiple <- tw_product("multiple") |>
    tw_add_source(orders) |>
    tw_add_source(data.frame(id = 1L), name = "other")
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(
      tw_product("root", multiple),
      multiple = data.frame(id = 2L)
    )
  )
})

test_that("corrections retain exact immutable references in unselected slots", {
  root <- withr::local_tempdir()
  config <- tw_lake_config(
    tw_registry_duckdb(file.path(root, "lake.db")),
    tw_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = "duckdb"
  )
  old <- run_result("run-1", "published", "release-1")
  old$asset <- "orders"
  old$output_config <- config
  fresh <- old
  fresh$run_id <- "run-2"
  fresh$release_id <- "release-2"
  definition <- tw_product("report") |>
    tw_add_source(old, name = "current") |>
    tw_add_source(old, name = "historical")
  corrected <- tw_replace_sources(definition, current = fresh)
  expect_identical(corrected$sources$historical, definition$sources$historical)
  expect_equal(corrected$sources$current$release_id, "release-2")
  expect_equal(list.files(root), character())
})
