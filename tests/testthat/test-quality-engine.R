test_that("formula engines preserve lexical scope and identical row evidence", {
  skip_if_not_installed("pointblank")
  predicate <- local({
    cutoff <- 10
    ~ amount >= cutoff
  })
  data <- data.frame(amount = c(10, 9, NA_real_))
  evidence <- lapply(c("native", "pointblank"), function(engine) {
    tw_run_quality(
      tw_quality_rule("minimum", predicate, engine = engine),
      data,
      keep_agent = TRUE
    )
  })
  columns <- c("rule", "status", "severity", "n_failed", "n_total", "threshold")
  expect_equal(
    lapply(columns, \(column) evidence[[1]][[column]]),
    lapply(columns, \(column) evidence[[2]][[column]])
  )
  expect_equal(evidence[[2]]$n_failed, 2)
  expect_equal(evidence[[2]]$n_total, 3)
  expect_identical(evidence[[2]]$engine, "pointblank")
  expect_s3_class(attr(evidence[[2]], "pointblank_agent"), "ptblank_agent")
  expect_match(evidence[[2]]$details, "col_vals_equal", fixed = TRUE)
  expect_match(evidence[[2]]$details, "amount >= cutoff", fixed = TRUE)
})

test_that("simple formulas and reusable rule lists share the optional engine", {
  skip_if_not_installed("pointblank")
  checks <- list(positive = ~ amount > 0, known = ~ kind %in% c("a", "b"))
  definition <- tw_product("orders") |>
    tw_add_source(data.frame(amount = c(1, 2), kind = c("a", "b"))) |>
    tw_add_quality(checks, engine = "pointblank")
  expect_equal(
    vapply(definition$quality, `[[`, character(1), "engine"),
    rep("pointblank", 2)
  )
  result <- tw_run(definition)
  expect_identical(result$status, "completed")
  expect_setequal(
    tw_quality(result)$rule[tw_quality(result)$engine == "pointblank"],
    names(checks)
  )
  reused <- tw_quality_rule("positive", ~ amount > 0, engine = "pointblank")
  expect_identical(
    tw_add_quality(tw_product("x"), reused)$quality[[1]]$engine,
    "pointblank"
  )
  expect_identical(
    tw_add_quality(tw_product("x"), reused, engine = "native")$quality[[
      1
    ]]$engine,
    "r"
  )
})

test_that("formula engines reject malformed outputs and keep empty evidence closed", {
  skip_if_not_installed("pointblank")
  data <- data.frame(amount = 1:3)
  for (engine in c("native", "pointblank")) {
    for (predicate in list(~1, ~ c(TRUE, FALSE), ~ matrix(TRUE, 3, 1))) {
      error <- tryCatch(
        tw_run_quality(
          tw_quality_rule("bad", predicate, engine = engine),
          data
        ),
        error = identity
      )
      expect_s3_class(error, "tw_error")
      expect_match(conditionMessage(error), "one logical value or one per row")
    }
    unknown <- tw_run_quality(
      tw_quality_rule("unknown", ~NA, engine = engine),
      data
    )
    expect_equal(unknown$n_failed, 3)
    expect_identical(unknown$status, "failed")
    scalar <- tw_run_quality(
      tw_quality_rule("constant", ~TRUE, engine = engine),
      data
    )
    expect_equal(scalar$n_total, 3)
    empty <- tw_run_quality(
      tw_quality_rule("empty", ~ amount > 0, engine = engine),
      data[0, , drop = FALSE]
    )
    expect_identical(empty$status, "not_checked")
    expect_identical(quality_ok(empty), FALSE)
  }
})

test_that("formula threshold boundaries and warning gates agree across engines", {
  skip_if_not_installed("pointblank")
  data <- data.frame(amount = c(1, -1, NA_real_))
  for (engine in c("native", "pointblank")) {
    equal <- tw_quality_rule(
      "limit",
      ~ amount > 0,
      max_failure = 2 / 3,
      engine = engine
    )
    expect_identical(tw_run_quality(equal, data)$status, "passed")
    warning <- tw_quality_rule(
      "limit",
      ~ amount > 0,
      severity = "warning",
      max_failure = 0.5,
      engine = engine
    )
    expect_identical(tw_run_quality(warning, data)$status, "warning")
  }
})

test_that("failed or empty formula evidence prevents every writer", {
  skip_if_not_installed("pointblank")
  local_adapter_method(
    "tw_check_component",
    "quality_gate_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "tw_write_target",
    "quality_gate_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list()
    }
  )
  for (engine in c("native", "pointblank")) {
    writes <- 0L
    for (amount in list(c(1, -1), numeric())) {
      result <- tw_product("orders") |>
        tw_add_source(data.frame(amount = amount)) |>
        tw_add_contract(tw_contract(
          columns = c(amount = "numeric"),
          allow_empty = TRUE
        )) |>
        tw_add_quality(~ amount > 0, engine = engine) |>
        tw_set_target(structure(list(), class = "quality_gate_target")) |>
        tw_run(stop_on_failure = FALSE)
      expect_identical(result$status, "blocked")
      expect_equal(writes, 0L)
    }
  }
})

test_that("optional formula engines fail preflight without reading or writing", {
  reads <- writes <- 0L
  local_adapter_method(
    "tw_check_component",
    "quality_dependency_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "tw_write_target",
    "quality_dependency_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list()
    }
  )
  definition <- tw_product("orders") |>
    tw_add_source(function() {
      reads <<- reads + 1L
      data.frame(amount = 1)
    }) |>
    tw_add_quality(~ amount > 0, engine = "pointblank") |>
    tw_set_target(structure(list(), class = "quality_dependency_target"))
  local_mocked_bindings(need = function(package) {
    if (package == "pointblank") abort("Install optional package: pointblank")
  })
  error <- tryCatch(tw_run(definition), error = identity)
  expect_s3_class(error, "tw_error")
  expect_match(
    conditionMessage(error),
    "Install optional package: pointblank",
    fixed = TRUE
  )
  expect_equal(c(reads, writes), c(0L, 0L))
})

test_that("pointblank formulas remain lazy and ungrouped like native predicates", {
  skip_if_not_installed("pointblank")
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  input <- data.frame(group = c("a", "a", "b"), amount = c(1, -1, NA_real_))
  DBI::dbWriteTable(con, "quality_data", input)
  lazy <- dplyr::tbl(con, "quality_data") |> dplyr::group_by(group)
  predicate <- local({
    floor <- 0
    ~ amount > floor
  })
  rule <- tw_quality_rule("minimum", predicate, engine = "pointblank")
  output <- tw_run_quality(rule, lazy, keep_agent = TRUE)
  expect_equal(output$n_failed, 2)
  expect_equal(output$n_total, 3)
  agent <- attr(output, "pointblank_agent")
  expect_s3_class(agent$tbl, "tbl_sql")
  expect_equal(dplyr::group_vars(agent$tbl), character())
  native <- tw_run_quality(tw_quality_rule("minimum", predicate), input)
  columns <- c("status", "n_failed", "n_total")
  expect_equal(
    lapply(columns, \(column) output[[column]]),
    lapply(columns, \(column) native[[column]])
  )
})

test_that("formula-engine configuration errors explain the custom-agent escape hatch", {
  expect_snapshot(
    error = TRUE,
    tw_quality_rule("bad", function(data) TRUE, engine = "pointblank")
  )
})
