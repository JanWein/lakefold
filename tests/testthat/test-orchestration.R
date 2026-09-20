test_that("targets runs each dependency once and tracks changed input files", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  utils::write.csv(
    data.frame(id = 1:2, amount = c(10, 20)),
    "input.csv",
    row.names = FALSE
  )
  writeLines(
    c(
      "library(tidyweave)",
      "orders_definition <- product('orders') |> add_source('input.csv')",
      "totals_definition <- product('totals') |> add_source(orders_definition) |> add_transform(function(data) data.frame(total = sum(data$amount)))",
      "unrelated_definition <- product('unrelated') |> add_source(data.frame(id = 1L))",
      "as_targets(list(totals = totals_definition, unrelated = unrelated_definition), evidence = './evidence')"
    ),
    "_targets.R"
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  first <- run_history("evidence")
  expect_equal(nrow(first), 3L)
  expect_equal(collect(targets::tar_read(totals))$total, 30)
  expect_equal(
    targets::tar_read(totals)$inputs$run_id,
    targets::tar_read(orders)$run_id
  )
  expect_equal(targets::tar_read(totals)$inputs$asset, "orders")
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(nrow(run_history("evidence")), 3L)
  utils::write.csv(
    data.frame(id = 1:2, amount = c(15, 25)),
    "input.csv",
    row.names = FALSE
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(nrow(run_history("evidence")), 5L)
  expect_equal(collect(targets::tar_read(totals))$total, 40)
})

test_that("targets tracks auxiliary lookup files and preserves upstream provenance", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  utils::write.csv(
    data.frame(id = 1:2, amount = c(10, 20)),
    "orders.csv",
    row.names = FALSE
  )
  write_rates <- function(rate) {
    utils::write.csv(
      data.frame(id = 1:2, rate = rate),
      "rates.csv",
      row.names = FALSE
    )
  }
  write_rates(c(1, 2))
  writeLines(
    c(
      "library(tidyweave)",
      "rates_definition <- product('rates', 'rates.csv')",
      "summary_definition <- product('summary', 'orders.csv') |> dplyr::mutate(amount = amount * 2) |> add_lookup(rates_definition, by = 'id') |> dplyr::mutate(total = amount * rate) |> dplyr::summarise(total = sum(total))",
      "unrelated_definition <- product('unrelated', data.frame(id = 1L))",
      "as_targets(list(summary_definition, unrelated_definition), evidence = 'evidence')"
    ),
    "_targets.R"
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  first <- targets::tar_read(summary)
  expect_equal(collect(first)$total, 100)
  expect_equal(nrow(run_history("evidence")), 3L)
  expect_equal(
    first$inputs$run_id[first$inputs$asset %in% "rates"],
    targets::tar_read(rates)$run_id
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(nrow(run_history("evidence")), 3L)
  write_rates(c(2, 2))
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(collect(targets::tar_read(summary))$total, 120)
  expect_equal(nrow(run_history("evidence")), 5L)
})

test_that("targets graph construction defers execution and rejects live handles", {
  skip_if_not_installed("targets")
  calls <- 0L
  definition <- product("orders") |>
    add_source(function() {
      calls <<- calls + 1L
      data.frame(id = 1L)
    })
  graph <- as_targets(definition)
  expect_length(graph, 1L)
  expect_equal(calls, 0L)
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  definition <- product("database") |>
    add_source(source_database(table = "orders", connection = con))
  error <- tryCatch(as_targets(definition), error = identity)
  expect_match(conditionMessage(error), "connection factories", fixed = TRUE)
})

test_that("targets observes globals used inside ordinary transform functions", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  script <- c(
    "library(tidyweave)",
    "multiplier <- 2",
    "orders_definition <- product('orders') |> add_source(data.frame(amount = 10)) |> add_transform(function(data) transform(data, amount = amount * multiplier))",
    "as_targets(orders_definition)"
  )
  writeLines(script, "_targets.R")
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(collect(targets::tar_read(orders))$amount, 20)
  script[[2]] <- "multiplier <- 3"
  writeLines(script, "_targets.R")
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(collect(targets::tar_read(orders))$amount, 30)
})

test_that("targets tracks static .env values in deferred dplyr expressions", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  script <- c(
    "library(tidyweave)",
    "multiplier <- 2",
    "orders_definition <- product('orders', data.frame(amount = 10)) |> dplyr::mutate(total = amount * .env$multiplier, second = amount * .env[['multiplier']])",
    "as_targets(orders_definition)"
  )
  writeLines(script, "_targets.R")
  targets::tar_make(callr_function = NULL, reporter = "silent")
  first <- targets::tar_read(orders)
  expect_equal(collect(first)$total, 20)
  expect_equal(collect(first)$second, 20)
  script[[2]] <- "multiplier <- 3"
  writeLines(script, "_targets.R")
  targets::tar_make(callr_function = NULL, reporter = "silent")
  second <- targets::tar_read(orders)
  expect_equal(collect(second)$total, 30)
  expect_equal(collect(second)$second, 30)
  expect_false(identical(second$run_id, first$run_id))
})

test_that("data-mask column names do not become product dependencies", {
  skip_if_not_installed("targets")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  writeLines(
    c(
      "library(tidyweave)",
      "a_definition <- product('a', data.frame(b = 1)) |> dplyr::mutate(value = b + 1)",
      "b_definition <- product('b', data.frame(a = 1)) |> dplyr::mutate(value = a + 1)",
      "as_targets(list(a_definition, b_definition))"
    ),
    "_targets.R"
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  expect_equal(collect(targets::tar_read(a))$value, 2)
  expect_equal(collect(targets::tar_read(b))$value, 2)
})

test_that("targets keeps lake definitions stable while recording new input releases", {
  skip_if_not_installed("targets")
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  write_input <- function(amount) {
    utils::write.csv(
      data.frame(id = 1:2, amount = amount),
      "input.csv",
      row.names = FALSE
    )
  }
  write_input(c(10, 20))
  writeLines(
    c(
      "library(tidyweave)",
      "orders_definition <- product('orders') |> add_source('input.csv') |> set_target('lake')",
      "explicit_definition <- product('explicit', version='1.0.0') |> add_source(orders_definition) |> set_target('lake')",
      "automatic_definition <- product('automatic') |> add_source(orders_definition) |> set_target('lake')",
      "as_targets(list(explicit_definition, automatic_definition))"
    ),
    "_targets.R"
  )
  targets::tar_make(callr_function = NULL, reporter = "silent")
  first_release <- targets::tar_read(orders)$release_id
  write_input(c(15, 25))
  targets::tar_make(callr_function = NULL, reporter = "silent")
  upstream <- targets::tar_read(orders)
  explicit <- targets::tar_read(explicit)
  automatic <- targets::tar_read(automatic)
  expect_equal(collect(explicit)$amount, c(15, 25))
  expect_equal(collect(automatic)$amount, c(15, 25))
  expect_equal(identical(first_release, upstream$release_id), FALSE)
  expect_equal(explicit$source_inputs$release_id, upstream$release_id)
  expect_equal(explicit$source_inputs$run_id, upstream$run_id)
  lake <- open_lake("lake", read_only = TRUE)
  withr::defer(close_lake(lake))
  definitions <- registry(lake, "assets")
  definitions <- definitions[
    definitions$kind == "composed_product" &
      definitions$id %in% c("explicit", "automatic"),
  ]
  expect_equal(nrow(definitions), 2L)
  expect_equal(definitions$version[definitions$id == "explicit"], "1.0.0")
})

test_that("direct and targets execution share the same lake product definition", {
  skip_if_not_installed("targets")
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  writeLines(
    c(
      "library(tidyweave)",
      "input_definition <- product('input') |> add_source(data.frame(id = 1L))",
      "reference_definition <- product('reference', data.frame(id = 1L, label = 'a'))",
      "output_definition <- product('output', version = '1.0.0') |> add_source(input_definition) |> add_lookup(reference_definition, by = 'id') |> set_target('lake')",
      "as_targets(output_definition)"
    ),
    "_targets.R"
  )
  definitions <- new.env(parent = globalenv())
  sys.source("_targets.R", envir = definitions)
  direct <- run(definitions$output_definition)
  targets::tar_make(callr_function = NULL, reporter = "silent")
  scheduled <- targets::tar_read(output)
  expect_equal(collect(scheduled), collect(direct))
  expect_equal(scheduled$status, "published")
  lake <- open_lake("lake", read_only = TRUE)
  withr::defer(close_lake(lake))
  assets <- registry(lake, "assets")
  expect_equal(
    sum(assets$id == "output" & assets$kind == "composed_product"),
    1L
  )
})

test_that("installed targets commands execute in a clean R process", {
  skip_if_not_installed("targets")
  installed <- file.exists(system.file(
    "Meta",
    "package.rds",
    package = "tidyweave"
  ))
  skip_if(!installed, "Requires an installed package for the separate R worker")
  root <- withr::local_tempdir()
  withr::local_dir(root)
  writeLines(
    c(
      "library(tidyweave)",
      "input_definition <- product('input') |> add_source(data.frame(id = 1:2))",
      "output_definition <- product('output') |> add_source(input_definition) |> add_transform(function(data) transform(data, doubled = id * 2))",
      "as_targets(output_definition)"
    ),
    "_targets.R"
  )
  targets::tar_make(reporter = "silent")
  first <- targets::tar_read(output)
  expect_equal(collect(first)$doubled, c(2, 4))
  expect_equal(first$inputs$run_id, targets::tar_read(input)$run_id)
  targets::tar_make(reporter = "silent")
  expect_equal(targets::tar_read(output)$run_id, first$run_id)
})
