test_that("the cancellation reference retains cohort grain and issued reports", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dm")
  customers_data <- tibble::tibble(
    customer_id = c("C1", "C2", "C3"),
    segment = c("Private", "Private", "Business")
  )
  brokers_data <- tibble::tibble(
    broker_id = c("B1", "B2"),
    channel = c("Broker", "Direct")
  )
  policies_data <- tibble::tibble(
    policy_id = paste0("P", 1:8),
    customer_id = c("C1", "C1", "C2", "C2", "C3", "C3", "C1", "C2"),
    broker_id = c("B1", "B1", "B2", "B2", "B1", "B2", "B1", "B2"),
    started_on = as.Date(c(
      rep("2026-01-01", 4),
      "2026-08-10",
      "2026-01-01",
      "2026-01-01",
      "2026-08-01"
    )),
    cancelled_on = as.Date(c(
      NA,
      "2026-08-01",
      "2026-08-31",
      "2026-09-01",
      "2026-08-20",
      "2025-12-31",
      NA,
      NA
    ))
  )

  customer_contract <- dr_contract(
    columns = c(customer_id = "character", segment = "character"),
    key = "customer_id",
    grain = "One customer"
  )
  broker_contract <- dr_contract(
    columns = c(broker_id = "character", channel = "character"),
    key = "broker_id",
    grain = "One broker"
  )
  policy_contract <- dr_contract(
    columns = c(
      policy_id = "character",
      customer_id = "character",
      broker_id = "character",
      started_on = "Date",
      cancelled_on = "Date"
    ),
    required = c("policy_id", "customer_id", "broker_id", "started_on"),
    key = "policy_id",
    grain = "One policy with at most one cancellation",
    rules = list(
      date_order = ~ is.na(cancelled_on) | cancelled_on >= started_on
    )
  )
  customers <- dr_product(
    "customers",
    customers_data,
    contract = customer_contract
  )
  brokers <- dr_product("brokers", brokers_data, contract = broker_contract)
  policies <- dr_product("policies", policies_data, contract = policy_contract)

  attempt <- dr_trial(policies)
  stopifnot(identical(dr_quality_rows(attempt)$policy_id, "P6"))
  fixed_policies <- policies_data
  fixed_policies$cancelled_on[fixed_policies$policy_id == "P6"] <- as.Date(
    "2026-07-31"
  )
  policies <- dr_replace_sources(policies, policies = fixed_policies)
  stopifnot(nrow(dr_collect(dr_trial(policies))) == 8L)

  portfolio_model <- dm::dm(
    customers = dr_collect(dr_trial(customers)),
    policies = dr_collect(dr_trial(policies)),
    brokers = dr_collect(dr_trial(brokers))
  ) |>
    dm::dm_add_pk(customers, customer_id) |>
    dm::dm_add_pk(policies, policy_id) |>
    dm::dm_add_pk(brokers, broker_id) |>
    dm::dm_add_fk(policies, customer_id, customers) |>
    dm::dm_add_fk(policies, broker_id, brokers)
  stopifnot(all(dm::dm_examine_constraints(portfolio_model)$is_key))

  portfolio <- dr_product("portfolio", portfolio_model) |>
    dr_replace_sources(
      customers = customers,
      policies = policies,
      brokers = brokers
    )
  checked_model <- dr_trial(portfolio)

  reporting_month <- function(data, from, until) {
    data |>
      dplyr::mutate(
        opening = started_on < from &
          (is.na(cancelled_on) | cancelled_on >= from),
        cancelled = opening &
          !is.na(cancelled_on) &
          cancelled_on >= from &
          cancelled_on < until
      )
  }
  reporting_product <- function(model_result) {
    dr_product("august_portfolio", model_result, table = "policies") |>
      dr_add_lookup(model_result, table = "customers", by = "customer_id") |>
      dr_add_lookup(model_result, table = "brokers", by = "broker_id") |>
      dr_add_transform(\(data) {
        reporting_month(data, as.Date("2026-08-01"), as.Date("2026-09-01"))
      })
  }
  august <- reporting_product(checked_model)
  define_cancellation_metrics <- function(
    approved = FALSE,
    code_version = NULL
  ) {
    dr_metric_set(
      "august_portfolio",
      opening = sum(opening, na.rm = TRUE),
      cancellations = sum(cancelled, na.rm = TRUE),
      cancellation_rate = if (sum(opening, na.rm = TRUE) == 0) {
        NA_real_
      } else {
        sum(cancelled, na.rm = TRUE) / sum(opening, na.rm = TRUE)
      },
      dimensions = "channel",
      units = c(
        opening = "policies",
        cancellations = "policies",
        cancellation_rate = "ratio"
      ),
      na_policy = "expression",
      approved = approved,
      code_version = code_version
    )
  }
  cancellation_metrics <- define_cancellation_metrics()
  preview <- dr_trial(august)
  values <- dr_measure(
    preview,
    metrics = cancellation_metrics,
    by = character()
  )
  stopifnot(
    nrow(dr_collect(preview)) == 8L,
    sum(dr_collect(preview)$opening) == 5,
    sum(dr_collect(preview)$cancelled) == 2
  )

  root <- withr::local_tempdir()
  first_model <- dr_publish(portfolio, to = root)
  first <- dr_publish(reporting_product(first_model), to = root)
  reviewed_metrics <- define_cancellation_metrics(
    approved = TRUE,
    code_version = "opening-cohort-v1"
  )
  first_values <- dr_measure(
    first,
    metrics = reviewed_metrics,
    by = character()
  )
  dr_report_release(first_values, "august-original", code_version = "report-v1")

  corrected_policies <- fixed_policies
  corrected_policies$cancelled_on[
    corrected_policies$policy_id == "P7"
  ] <- as.Date("2026-08-15")
  second_model <- dr_publish(
    portfolio,
    to = root,
    previous = first_model,
    sources = list(policies = corrected_policies)
  )
  second <- dr_publish(
    reporting_product(second_model),
    to = root,
    previous = first
  )
  second_values <- dr_measure(
    second,
    metrics = reviewed_metrics,
    by = character()
  )
  dr_report_release(
    second_values,
    "august-corrected",
    code_version = "report-v1"
  )
  original <- dr_report_read(root, "august-original", values_only = TRUE)
  corrected <- dr_report_read(root, "august-corrected", values_only = TRUE)
  stopifnot(
    original$value[original$.metric == "cancellation_rate"] == 0.4,
    corrected$value[corrected$.metric == "cancellation_rate"] == 0.6
  )
  stopifnot(
    sum(dr_collect(first)$cancelled) == 2,
    sum(dr_collect(second)$cancelled) == 3,
    sum(dr_collect(second)$opening) == 5
  )

  rate <- function(x) x$value[x$.metric == "cancellation_rate"]
  expect_equal(rate(original), 0.4)
  expect_equal(rate(corrected), 0.6)
  data <- dr_collect(dr_trial(august))
  expect_equal(data$policy_id[data$opening], c("P1", "P2", "P3", "P4", "P7"))
  expect_equal(data$policy_id[data$cancelled], c("P2", "P3"))

  no_opening <- fixed_policies
  no_opening$started_on <- as.Date("2026-08-01")
  no_opening$cancelled_on <- as.Date(NA)
  empty_cohort <- dr_trial(reporting_product(dr_trial(
    portfolio,
    sources = list(policies = no_opening)
  )))
  counts <- dr_collect(dr_measure(
    empty_cohort,
    metrics = cancellation_metrics[c("opening", "cancellations")],
    by = "channel"
  ))
  expect_equal(counts$value, rep(0, 4))
  error <- tryCatch(
    dr_measure(
      empty_cohort,
      metrics = cancellation_metrics,
      by = "channel"
    ),
    error = identity
  )
  expect_s3_class(error, "dataraft_error")
  expect_match(conditionMessage(error), "missing or non-finite")

  duplicate <- rbind(customers_data, customers_data[1, ])
  blocked <- dr_trial(portfolio, sources = list(customers = duplicate))
  expect_equal(blocked$status %in% c("blocked", "error"), TRUE)
  orphan <- fixed_policies
  orphan$customer_id[1] <- "missing"
  blocked <- dr_trial(portfolio, sources = list(policies = orphan))
  expect_equal(blocked$status %in% c("blocked", "error"), TRUE)
})
