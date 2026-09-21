test_that("products normalize contracts and metadata through one class", {
  x <- tw_product("orders", contract = c(id = "integer"))
  y <- tw_product("orders") |>
    tw_add_contract(tw_contract(
      columns = c(id = "integer"),
      owner = "Analytics",
      description = "Order records"
    ))
  expect_identical(class(x), "tw_product")
  expect_identical(class(y), class(x))
  expect_identical(tw_inspect(y)$owner, "Analytics")
  expect_identical(tw_inspect(y)$description, "Order records")
  expect_null(x$contract$max_age_hours)
})

test_that("named sources accumulate and replacement is explicit", {
  a <- data.frame(id = 1:2)
  b <- data.frame(id = 1:2, value = c(10, 20))
  x <- tw_product("joined") |>
    tw_add_source(a, "keys") |>
    tw_add_source(b, "values")
  expect_named(x$sources, c("keys", "values"))
  expect_error(tw_add_source(x, b, "keys"), "replace = TRUE")
  replaced <- tw_add_source(x, data.frame(id = 2L), "keys", replace = TRUE)
  x <- x |>
    tw_add_transform(function(data) merge(data$keys, data$values, by = "id"))
  expect_equal(tw_collect(tw_run(x))$value, c(10, 20))
  expect_equal(replaced$sources$keys$id, 2L)
  expect_error(tw_run(replaced), class = "tw_run_failed")
  failed <- tw_run(replaced, stop_on_failure = FALSE)
  expect_match(conditionMessage(failed$error), "Combine multiple sources")
})

test_that("shared dependencies execute once and invalid graphs fail before IO", {
  calls <- 0L
  shared <- tw_product("shared") |>
    tw_add_source(function() {
      calls <<- calls + 1L
      data.frame(id = 1:2)
    })
  left <- tw_product("left") |> tw_add_source(shared)
  right <- tw_product("right") |> tw_add_source(shared)
  joined <- tw_product("joined") |>
    tw_add_source(left) |>
    tw_add_source(right) |>
    tw_add_transform(function(data) merge(data$left, data$right, by = "id"))
  expect_equal(tw_collect(tw_run(joined))$id, 1:2)
  expect_equal(calls, 1L)
  cycle <- shared |> tw_add_source(left)
  expect_error(tw_run(cycle), class = "tw_dependency_cycle")
  expect_equal(calls, 1L)
  alternate <- shared |> tw_add_transform(identity)
  conflict <- joined
  conflict$sources$right$sources$shared <- alternate
  expect_error(tw_run(conflict), class = "tw_dependency_conflict")
  expect_equal(calls, 1L)
})

test_that("sources are acquired once and lazy DBI results stay lazy", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "orders", data.frame(id = 1:3, amount = c(10, 20, 30)))
  calls <- 0L
  source <- function() {
    calls <<- calls + 1L
    dplyr::tbl(con, "orders")
  }
  transform <- function(data) dplyr::filter(data, amount > 10)
  lazy <- tw_product("orders") |>
    tw_add_source(source) |>
    tw_add_transform(transform) |>
    tw_add_quality(~ amount > 0)
  result <- tw_run(lazy)
  expect_s3_class(result$data, "tbl_sql")
  expect_identical(tw_inspect(result$data)$columns, c("id", "amount"))
  expect_equal(tw_collect(result)$id, 2:3)
  expect_equal(calls, 1L)
  expect_equal(result$inputs$hash_kind, "definition")
  ordinary <- tw_product("orders") |>
    tw_add_source(DBI::dbReadTable(con, "orders")) |>
    tw_add_transform(transform)
  expect_equal(tw_collect(tw_run(ordinary)), tw_collect(result))
  expect_true(DBI::dbIsValid(con))
  expect_true(tw_capabilities(tw_source_database(con, "orders"))$lazy)
  expect_error(
    tw_source_database(function() con, "orders", lazy = TRUE),
    "lazy = FALSE"
  )
})

test_that("capabilities use one stable shape and explain materialization", {
  expected <- c(
    "read",
    "write",
    "lazy",
    "transactions",
    "partition",
    "immutable"
  )
  expect_named(tw_capabilities(identity), expected)
  expect_true(is.na(tw_capabilities(identity)$lazy))
  expect_identical(tw_capabilities(NULL)$lazy, TRUE)
  expect_error(tw_component_capabilities(lazy = "yes"), "TRUE, FALSE or NA")
  x <- tw_product("orders") |> tw_add_source(data.frame(id = 1L))
  expect_named(tw_inspect(x)$sources, "source_1")
  expect_true("materializes" %in% names(tw_plan(x)))
  expect_output(tw_explain(x), "collect\\(\\) materializes")
})

test_that("multiple lake sources preserve original bytes and pinned lineage", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  lake <- tw_open_lake(file.path(root, "lake"))
  withr::defer(tw_close_lake(lake))
  a <- file.path(root, "keys.csv")
  b <- file.path(root, "values.csv")
  utils::write.csv(data.frame(id = 1:2), a, row.names = FALSE)
  utils::write.csv(
    data.frame(id = 1:2, amount = c(10, 20)),
    b,
    row.names = FALSE
  )
  reads <- 0L
  reader <- function(path) {
    reads <<- reads + 1L
    utils::read.csv(path)
  }
  x <- tw_product("joined") |>
    tw_add_source(a, "keys", reader = reader) |>
    tw_add_source(b, "values", reader = reader) |>
    tw_add_transform(function(data) merge(data$keys, data$values, by = "id")) |>
    tw_set_target(lake)
  result <- tw_run(x)
  expect_equal(reads, 2L)
  expect_equal(tw_collect(result)$amount, c(10, 20))
  originals <- result$inputs[
    result$inputs$original_name %in% c("keys.csv", "values.csv"),
  ]
  expect_equal(nrow(originals), 2L)
  expect_true(all(file.exists(originals$landed_path)))
  for (i in seq_len(nrow(originals))) {
    path <- file.path(root, originals$original_name[[i]])
    expect_identical(
      readBin(path, "raw", n = file.info(path)$size),
      readBin(originals$landed_path[[i]], "raw", n = file.info(path)$size)
    )
  }
  derived <- tw_product("copy") |>
    tw_add_source(tw_source_release(lake, "joined")) |>
    tw_set_target(lake)
  copied <- tw_run(derived)
  expect_true(result$release_id %in% copied$inputs$source_version)
  edges <- copied$metadata$lineage
  expect_true(result$release_id %in% edges$from_version)
})


test_that("writer candidate evidence is distinguished from the submitted batch", {
  local_adapter_method(
    "tw_write_target",
    "candidate_target",
    function(target, data, context, ...) {
      candidate <- rbind(data.frame(id = 1L), data)
      checks <- tw_validate(candidate, context$contract)
      if (!quality_ok(checks)) {
        abort(
          "Candidate rejected.",
          "tw_target_quality_failed",
          quality = checks
        )
      }
      list(
        type = "candidate",
        rows = nrow(candidate),
        written_rows = nrow(data),
        candidate_quality = checks
      )
    }
  )
  local_adapter_method(
    "tw_check_component",
    "candidate_target",
    function(x, ...) {
      invisible(x)
    }
  )
  x <- tw_product(
    "orders",
    contract = tw_contract(columns = c(id = "integer"), key = "id")
  ) |>
    tw_add_source(data.frame(id = 2L)) |>
    tw_set_target(structure(list(), class = "candidate_target"))
  result <- tw_run(x)
  expect_equal(result$metadata$rows, 2)
  expect_equal(result$metadata$submitted_rows, 1)
  expect_equal(tw_collect(result)$id, 2L)
  expect_equal(result$quality$n_total[result$quality$rule == "unique_key"], 2)
  failed <- tw_run(
    x |> tw_add_source(data.frame(id = 1L), "source_1", replace = TRUE),
    stop_on_failure = FALSE
  )
  expect_identical(failed$status, "blocked")
  expect_true(any(failed$quality$status == "failed"))
})
