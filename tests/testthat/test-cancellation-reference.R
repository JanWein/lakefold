test_that("the cancellation reference retains cohort grain and issued reports", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dm")
  example <- new.env(parent = globalenv())
  sys.source(
    system.file(
      "examples",
      "cancellation_report.R",
      package = "tidyweave",
      mustWork = TRUE
    ),
    envir = example
  )
  rate <- function(x) x$value[x$.metric == "cancellation_rate"]
  expect_equal(rate(example$original), 0.4)
  expect_equal(rate(example$corrected), 0.6)
  data <- collect(trial(example$august))
  expect_equal(data$policy_id[data$opening], c("P1", "P2", "P3", "P4", "P7"))
  expect_equal(data$policy_id[data$cancelled], c("P2", "P3"))

  no_opening <- example$fixed_policies
  no_opening$started_on <- as.Date("2026-08-01")
  no_opening$cancelled_on <- as.Date(NA)
  empty_cohort <- trial(example$reporting_product(trial(
    example$portfolio,
    sources = list(policies = no_opening)
  )))
  counts <- collect(measure(
    empty_cohort,
    metrics = example$cancellation_metrics[c("opening", "cancellations")],
    by = "channel"
  ))
  expect_equal(counts$value, rep(0, 4))
  error <- tryCatch(
    measure(
      empty_cohort,
      metrics = example$cancellation_metrics,
      by = "channel"
    ),
    error = identity
  )
  expect_s3_class(error, "tw_error")
  expect_match(conditionMessage(error), "missing or non-finite")

  duplicate <- rbind(example$customers_data, example$customers_data[1, ])
  blocked <- trial(example$portfolio, sources = list(customers = duplicate))
  expect_equal(blocked$status %in% c("blocked", "error"), TRUE)
  orphan <- example$fixed_policies
  orphan$customer_id[1] <- "missing"
  blocked <- trial(example$portfolio, sources = list(policies = orphan))
  expect_equal(blocked$status %in% c("blocked", "error"), TRUE)
})
