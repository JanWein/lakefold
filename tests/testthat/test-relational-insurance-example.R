test_that("the insurance example preserves business grains and issued reports", {
  executable <- Sys.getenv("TIDYWEAVE_DBT_EXECUTABLE")
  skip_if(
    !nzchar(executable),
    "Set TIDYWEAVE_DBT_EXECUTABLE for the real insurance dbt integration test"
  )
  for (package in c("duckdb", "pointblank", "dm", "yaml", "processx")) {
    skip_if_not_installed(package)
  }
  example <- new.env(parent = asNamespace("tidyweave"))
  sys.source(
    system.file(
      "examples",
      "relational-insurance.R",
      package = "tidyweave",
      mustWork = TRUE
    ),
    envir = example
  )
  demo <- example$run_relational_insurance(
    path = withr::local_tempdir(),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb"),
    executable = executable
  )

  # Handwritten business expectations retain the inactive, zero-cash group.
  expected <- tibble::tibble(
    company = rep(c("Harbor", "Northstar", "Northstar"), 2),
    channel = rep(c("partner", "broker", "direct"), 2),
    month = rep(as.Date(c("2026-01-01", "2026-02-01")), each = 3),
    active_policies = c(2L, 2L, 1L, 2L, 3L, 0L),
    premium_due = c(900, 300, 300, 900, 450, 0),
    payment_count = c(1L, 3L, 1L, 2L, 3L, 0L),
    cash_collected = c(400, 280, 300, 850, 450, 0)
  )
  ordered <- function(data) {
    dplyr::arrange(data, month, company, channel)
  }
  expect_equal(ordered(demo$initial$data), expected)
  corrected <- expected
  corrected$cash_collected[[1]] <- 650
  corrected$payment_count[[1]] <- 2L
  expect_equal(ordered(demo$corrected$data), corrected)

  policies <- collect(demo$products$policies)
  payments <- collect(demo$products$payments)
  expect_equal(nrow(policies), 12L)
  expect_equal(nrow(payments), 10L)
  expect_equal(anyDuplicated(policies[c("policy_id", "month")]), 0L)
  expect_equal(anyDuplicated(payments$payment_id), 0L)
  january <- as.Date("2026-01-01")
  first_policy <- policies$policy_id == "P1" & policies$month == january
  first_payments <- payments$policy_id == "P1" & payments$month == january
  expect_equal(policies$premium_due[first_policy], 100)
  expect_equal(sum(first_payments), 2L)
  expect_equal(sum(payments$cash_amount[first_payments]), 100)
  expect_equal(sum(policies$premium_due), 2850)
  expect_setequal(
    demo$definitions$policies$contract$key,
    c("policy_id", "month")
  )
  expect_identical(demo$definitions$payments$contract$key, "payment_id")
  for (accepted in demo$raw) {
    checks <- quality(accepted)
    expect_gt(sum(checks$engine == "pointblank" & checks$stage == "ingest"), 0L)
    expect_identical(accepted$status, "published")
    expect_identical(accepted$outputs$schema, "raw")
  }

  # Ratios aggregate the numerator and denominator, not individual percentages.
  expect_equal(demo$initial$measures$ratio_total$value, 2280 / 2850)
  expect_gt(
    abs(
      demo$initial$measures$ratio_total$value - mean(c(980 / 1500, 1300 / 1350))
    ),
    0.001
  )
  expect_equal(demo$corrected$measures$ratio_total$value, 2530 / 2850)
  expect_identical(demo$failures$pointblank$status, "blocked")
  expect_null(demo$failures$pointblank$outputs)
  expect_identical(unique(quality(demo$failures$pointblank)$stage), "ingest")
  expect_gt(nrow(demo$failures$pointblank$inputs), 0L)
  expect_equal(
    sum(file.exists(demo$failures$pointblank$inputs$landed_path)),
    nrow(demo$failures$pointblank$inputs)
  )
  expect_identical(demo$failures$dm$result$status, "error")
  expect_identical(
    demo$failures$dm$current_release,
    demo$products$policies$release_id
  )

  # A known policy in an unknown month exercises the composite foreign key.
  invalid <- collect(demo$corrected$raw$payments)
  invalid$month[[1]] <- as.Date("2026-03-01")
  failed <- demo$definitions$payments |>
    add_source(invalid, name = "payments", replace = TRUE) |>
    run(stop_on_failure = FALSE)
  expect_identical(failed$status, "error")
  expect_null(failed$outputs)
  expect_s3_class(failed$error, "tw_transform_failed")
  expect_s3_class(failed$error$parent, "insurance_relationship_error")

  lake <- connect_lake(demo$context$config, read_only = TRUE)
  withr::defer(close_lake(lake))
  # Both builds must identify the exact independently approved staging releases.
  for (phase in c("initial", "corrected")) {
    results <- if (phase == "initial") {
      demo$products
    } else {
      demo$corrected$products
    }
    built <- demo[[phase]]$build
    expect_identical(built$success, TRUE)
    for (name in names(results)) {
      source <- built$manifest$sources[[
        paste0("source.insurance.accepted_products.", name)
      ]]
      history <- releases(lake, results[[name]]$asset)
      reference <- history[history$release_id == results[[name]]$release_id, ]
      expect_equal(nrow(reference), 1L)
      expect_identical(source$database, "lake")
      expect_identical(source$schema, "staging")
      expect_identical(source$schema, reference$schema_name[[1]])
      expect_identical(source$identifier, reference$table_name[[1]])
      metadata <- source$config$meta$tidyweave
      if (is.null(metadata)) {
        metadata <- source$meta$tidyweave
      }
      expect_identical(metadata$release_id, results[[name]]$release_id)
      expect_identical(metadata$asset, results[[name]]$asset)
    }
  }

  expect_identical(
    releases(lake, demo$products$policies$asset)$release_id,
    demo$products$policies$release_id
  )
  expect_setequal(
    releases(lake, demo$products$payments$asset)$release_id,
    c(
      demo$products$payments$release_id,
      demo$corrected$products$payments$release_id
    )
  )
  expect_equal(
    collect(read_release(lake, demo$initial$release$asset)) |> ordered(),
    corrected
  )
  expect_equal(
    read_release(
      lake,
      demo$initial$release$asset,
      release = demo$initial$release$release_id
    ) |>
      ordered(),
    expected
  )
  for (phase in c("initial", "corrected")) {
    report <- report_read(lake, demo[[phase]]$report$id)
    pins <- vapply(
      report$measures,
      function(x) x$manifest$release_id,
      character(1)
    )
    expect_identical(unname(unique(pins)), demo[[phase]]$release$release_id)
  }
  saved <- report_read(lake, demo$initial$report$id, values_only = TRUE)
  expect_equal(saved$cash_jan$value, 980)
  expect_equal(saved$cash_feb$value, 1300)
  expect_equal(saved$active_jan$value, 5L)
  expect_equal(saved$active_feb$value, 5L)
  expect_equal(saved$due_jan$value, 1500)
  expect_equal(saved$due_feb$value, 1350)
  stock_error <- tryCatch(
    measure(
      lake,
      demo$initial$metrics$active_policies,
      release = demo$initial$release$release_id
    ),
    error = identity
  )
  expect_s3_class(stock_error, "tw_error")
  expect_match(
    conditionMessage(stock_error),
    "Stock metrics require exactly one"
  )
  ratio_error <- tryCatch(
    measure(
      lake,
      demo$initial$metrics$cash_to_due,
      at = as.Date("2026-02-01"),
      filters = list(channel = "direct"),
      release = demo$initial$release$release_id
    ),
    error = identity
  )
  expect_s3_class(ratio_error, "tw_error")
  expect_match(conditionMessage(ratio_error), "non-finite")
})
