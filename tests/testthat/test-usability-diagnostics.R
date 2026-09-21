test_that("blocked results explain actual checks without counting rows twice", {
  definition <- product("orders", data.frame(amount = c(1, -2, 3))) |>
    add_quality(list(amount = ~ amount >= 0))
  result <- run(definition, stop_on_failure = FALSE)
  expect_equal(status(result)$outcome, "blocked")
  expect_match(status(result)$message, "orders is blocked", fixed = TRUE)
  expect_match(status(result)$message, "1 of 3 checks failed", fixed = TRUE)
  printed <- paste(capture.output(print(result)), collapse = "\n")
  expect_match(printed, "quality_rows(result)", fixed = TRUE)
  expect_false(grepl(result$run_id, printed, fixed = TRUE))
  expect_false(grepl("release: NA", printed, fixed = TRUE))
  expect_snapshot(error = TRUE, collect(result))
  report <- quality_report(result)
  expect_s3_class(report, "tbl_df")
  expect_equal(report$n_failed[report$rule == "amount"], 1)
  expect_equal(report$n_total[report$rule == "amount"], 3)
  expect_false("data" %in% names(report))
})

test_that("execution summaries distinguish completion from publication and redact errors", {
  done <- run(product("orders", data.frame(id = 1L)))
  expect_match(status(done)$message, "completed", fixed = TRUE)
  expect_false(grepl("published", status(done)$message, fixed = TRUE))
  missing <- run_result("secret-run-id", "missing")
  missing$error <- simpleError("token=SECRET and private source rows")
  expect_match(status(missing)$message, "delivery is missing", fixed = TRUE)
  expect_false(grepl(
    "SECRET",
    paste(capture.output(print(missing)), collapse = "")
  ))
  expect_equal(quality(missing)$status, "not_checked")
  expect_equal(quality_report(quality_row("", "")[0, ])$status, "not_checked")
})

test_that("measurement quality follows pinned evidence and preserves borrowed connections", {
  skip_if_not_installed("duckdb")
  f <- fixture()
  on.exit(fixture_cleanup(f))
  original <- run(f$pipeline, f$lake)
  measured <- measure(f$lake, metrics = list(reserve = reserve_metric()))
  # Explicit fixture reference also verifies the diagnostic reader independently.
  attr(measured[[1]], "tw_quality_reference") <- list(
    lake = f$lake,
    config = f$lake$config,
    asset = "risk.validated",
    release = original$release_id
  )
  f$write(transform(f$good, reserve = -1))
  blocked <- run(f$pipeline, f$lake, stop_on_failure = FALSE)
  expect_equal(blocked$status, "blocked")
  checks <- quality(measured)
  expect_equal(quality(measured[[1]]), checks)
  expect_equal(status(measured[[1]]), status(measured))
  expect_equal(lineage(measured[[1]]), lineage(measured))
  expect_true(all(checks$status %in% c("passed", "warning")))
  expect_true(all(checks$.release == original$release_id))
  expect_true(DBI::dbIsValid(f$lake$con))
  disconnect_lake(f$lake)
  expect_equal(quality(measured), checks)
  f$lake <- connect_lake(f$lake$config)
  expect_true(DBI::dbIsValid(f$lake$con))

  attr(measured[[1]], "tw_quality_reference")$release <- "different-release"
  expect_equal(quality(measured)$status, "not_checked")
  attr(measured[[1]], "tw_quality_reference") <- NULL
  expect_equal(quality_report(measured)$status, "not_checked")
})


test_that("large diagnoses stay concise without claiming allowed checks blocked", {
  checks <- dplyr::bind_rows(lapply(seq_len(5), function(i) {
    quality_row(paste0("rule_", i), "not_checked")
  }))
  result <- run_result("internal", "completed", quality = checks)
  result$asset <- "orders"
  text <- status(result)$message
  expect_match(text, "5 checks requiring attention", fixed = TRUE)
  expect_match(text, "2 more", fixed = TRUE)
  expect_false(grepl("rule_4", text, fixed = TRUE))
  expect_false(grepl("blocking", text, fixed = TRUE))
})


test_that("default failed runs explain checks and retain inspectable evidence", {
  definition <- product("orders", data.frame(amount = c(1, -2, 3))) |>
    add_quality(list(amount = ~ amount >= 0))
  expect_snapshot(error = TRUE, run(definition))
  failure <- tryCatch(run(definition), tw_run_failed = identity)
  expect_equal(failure$result$status, "blocked")
  expect_equal(
    quality(failure$result)$n_failed[quality(failure$result)$rule == "amount"],
    1
  )

  broken <- product("orders", data.frame(amount = 1)) |>
    add_transform(function(data) stop("token=TOP_SECRET"))
  failure <- tryCatch(run(broken), tw_run_failed = identity)
  expect_match(conditionMessage(failure), "orders failed", fixed = TRUE)
  expect_false(grepl("TOP_SECRET", conditionMessage(failure), fixed = TRUE))
  expect_match(
    conditionMessage(failure$result$error),
    "TOP_SECRET",
    fixed = TRUE
  )
  expect_s3_class(failure$parent, "tw_execution_cause")
})


test_that("nested failures surface upstream evidence without reexecuting sources", {
  raw <- product("raw", data.frame(amount = -2)) |>
    add_quality(list(amount = ~ amount > 0))
  prepared <- product("prepared", raw)
  report <- product("report", prepared)
  result <- run(report, stop_on_failure = FALSE)
  expect_false(status(result)$success)
  expect_match(status(result)$message, "Upstream: raw is blocked", fixed = TRUE)
  expect_match(status(result)$message, "1 of 1 checks failed", fixed = TRUE)
  expect_equal(quality(result)$n_failed[quality(result)$rule == "amount"], 1)
})


test_that("known definition failures retain safe reasons and actionable advice", {
  result <- run_result("internal", "error")
  result$asset <- "orders"
  result$error <- rlang::error_cnd(
    "tw_definition_changed",
    message = "private backend context token=SECRET",
    definition_id = "orders",
    definition_version = "1"
  )
  message <- status(result)$message
  expect_match(
    message,
    "Definition changed without a version bump: orders 1",
    fixed = TRUE
  )
  expect_match(message, "new version before publishing", fixed = TRUE)
  expect_false(grepl("SECRET", message, fixed = TRUE))
  result$error <- rlang::error_cnd("tw_read_only", message = "private endpoint")
  expect_match(status(result)$message, "Choose a writable target", fixed = TRUE)
  expect_false(grepl("private endpoint", status(result)$message, fixed = TRUE))
})
