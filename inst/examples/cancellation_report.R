library(tidyweave)
library(dplyr)
customers_data <- tibble(
  customer_id = c("C1", "C2", "C3"),
  segment = c("Private", "Private", "Business")
)
brokers_data <- tibble(
  broker_id = c("B1", "B2"),
  channel = c("Broker", "Direct")
)
policies_data <- tibble(
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

customer_contract <- contract(
  columns = c(customer_id = "character", segment = "character"),
  key = "customer_id",
  grain = "One customer"
)
broker_contract <- contract(
  columns = c(broker_id = "character", channel = "character"),
  key = "broker_id",
  grain = "One broker"
)
policy_contract <- contract(
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
  rules = list(date_order = ~ is.na(cancelled_on) | cancelled_on >= started_on)
)
customers <- product("customers", customers_data, contract = customer_contract)
brokers <- product("brokers", brokers_data, contract = broker_contract)
policies <- product("policies", policies_data, contract = policy_contract)

attempt <- trial(policies)
quality_rows(attempt)
stopifnot(identical(quality_rows(attempt)$policy_id, "P6"))
fixed_policies <- policies_data
fixed_policies$cancelled_on[fixed_policies$policy_id == "P6"] <- as.Date(
  "2026-07-31"
)
policies <- replace_sources(policies, policies = fixed_policies)
stopifnot(nrow(collect(trial(policies))) == 8L)

portfolio_model <- dm::dm(
  customers = collect(trial(customers)),
  policies = collect(trial(policies)),
  brokers = collect(trial(brokers))
) |>
  dm::dm_add_pk(customers, customer_id) |>
  dm::dm_add_pk(policies, policy_id) |>
  dm::dm_add_pk(brokers, broker_id) |>
  dm::dm_add_fk(policies, customer_id, customers) |>
  dm::dm_add_fk(policies, broker_id, brokers)
stopifnot(all(dm::dm_examine_constraints(portfolio_model)$is_key))

portfolio <- product("portfolio", portfolio_model) |>
  replace_sources(customers = customers, policies = policies, brokers = brokers)
checked_model <- trial(portfolio)
collect(checked_model)

reporting_month <- function(data, from, until) {
  data |>
    mutate(
      opening = started_on < from &
        (is.na(cancelled_on) | cancelled_on >= from),
      cancelled = opening &
        !is.na(cancelled_on) &
        cancelled_on >= from &
        cancelled_on < until
    )
}
reporting_product <- function(model_result) {
  product("august_portfolio", model_result, table = "policies") |>
    add_lookup(model_result, table = "customers", by = "customer_id") |>
    add_lookup(model_result, table = "brokers", by = "broker_id") |>
    add_transform(\(data) {
      reporting_month(data, as.Date("2026-08-01"), as.Date("2026-09-01"))
    })
}
august <- reporting_product(checked_model)
define_cancellation_metrics <- function(approved = FALSE, code_version = NULL) {
  metric_set(
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
preview <- trial(august)
values <- measure(preview, metrics = cancellation_metrics, by = character())
collect(values)
stopifnot(
  nrow(collect(preview)) == 8L,
  sum(collect(preview)$opening) == 5,
  sum(collect(preview)$cancelled) == 2
)


root <- tempfile("cancellation-reference-")
first_model <- publish(portfolio, to = root)
first <- publish(reporting_product(first_model), to = root)
reviewed_metrics <- define_cancellation_metrics(
  approved = TRUE,
  code_version = "opening-cohort-v1"
)
first_values <- measure(first, metrics = reviewed_metrics, by = character())
report_release(first_values, "august-original", code_version = "report-v1")

corrected_policies <- fixed_policies
corrected_policies$cancelled_on[
  corrected_policies$policy_id == "P7"
] <- as.Date("2026-08-15")
second_model <- publish(
  portfolio,
  to = root,
  previous = first_model,
  sources = list(policies = corrected_policies)
)
second <- publish(reporting_product(second_model), to = root, previous = first)
second_values <- measure(second, metrics = reviewed_metrics, by = character())
report_release(second_values, "august-corrected", code_version = "report-v1")
original <- report_read(root, "august-original", values_only = TRUE)
corrected <- report_read(root, "august-corrected", values_only = TRUE)
original
corrected
stopifnot(
  original$value[original$.metric == "cancellation_rate"] == 0.4,
  corrected$value[corrected$.metric == "cancellation_rate"] == 0.6
)
stopifnot(
  sum(collect(first)$cancelled) == 2,
  sum(collect(second)$cancelled) == 3,
  sum(collect(second)$opening) == 5
)

unlink(root, recursive = TRUE)
