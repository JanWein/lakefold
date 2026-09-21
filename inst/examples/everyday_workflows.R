knitr::opts_chunk$set(collapse = TRUE, comment = "#>", message = FALSE)
library(tidyweave)

payment_data <- data.frame(
  payment_id = c("T1", "T2", "T3"),
  policy_id = c("P1", "P2", "P3"),
  amount = c(100, 200, -50)
)
contract_data <- data.frame(
  policy_id = c("P1", "P2", "P3"),
  broker_id = c("B1", "B1", "B2"),
  company = c("North", "North", "South")
)
broker_data <- data.frame(
  broker_id = c("B1", "B2"),
  channel = c("Broker", "Direct")
)

payments <- product("payments", payment_data) |>
  add_lookup(contract_data, by = "policy_id", name = "contracts") |>
  add_lookup(broker_data, by = "broker_id", name = "brokers") |>
  add_contract(contract(
    columns = c(
      payment_id = "character",
      policy_id = "character",
      amount = "numeric",
      broker_id = "character",
      company = "character",
      channel = "character"
    ),
    key = "payment_id"
  )) |>
  add_quality(~ amount >= 0, name = "nonnegative")
payments

preview <- trial(payments)
preview
quality_report(preview)
quality_rows(preview)
stopifnot(identical(quality_rows(preview)$payment_id, "T3"))

fixed_payments <- payment_data
fixed_payments$amount[fixed_payments$payment_id == "T3"] <- 50
preview <- trial(payments, sources = list(payments = fixed_payments))
collect(preview)
stopifnot(sum(collect(preview)$amount) == 350)

metrics <- metric_set(
  "payments",
  total = sum(amount, na.rm = TRUE),
  dimensions = "company",
  units = "EUR"
)
preview_values <- measure(preview, metrics = metrics, by = "company")
preview_values
stopifnot(identical(collect(preview_values)$value, c(300, 50)))


root <- tempfile("tidyweave-everyday-")
payments <- payments |> set_target(root)
first <- publish(payments, sources = list(payments = fixed_payments))

# Only after business review: approval is your explicit declaration.
metrics <- metric_set(
  "payments",
  total = sum(amount, na.rm = TRUE),
  dimensions = "company",
  units = "EUR",
  approved = TRUE,
  code_version = "payment-totals-v1"
)
values <- measure(first, metrics = metrics, by = "company")
report_release(values, "august-v1", code_version = "report-v1")

corrected_payments <- fixed_payments
corrected_payments$amount[corrected_payments$payment_id == "T3"] <- 80
second <- publish(payments, sources = list(payments = corrected_payments))
difference <- compare(first, second)
difference
difference$changed

corrected_values <- measure(second, metrics = metrics, by = "company")
corrected_values
report_release(corrected_values, "august-v2", code_version = "report-v1")

corrected_contracts <- contract_data
corrected_contracts$company[corrected_contracts$policy_id == "P3"] <- "North"
third <- publish(
  payments,
  sources = list(
    payments = corrected_payments,
    contracts = corrected_contracts
  )
)
reference_values <- measure(third, metrics = metrics, by = "company")
reference_values
stopifnot(identical(collect(reference_values)$value, 380))

original_report <- report_read(root, "august-v1", values_only = TRUE)
corrected_report <- report_read(root, "august-v2", values_only = TRUE)
original_report
corrected_report
stopifnot(
  identical(as.numeric(original_report$value), c(300, 50)),
  identical(as.numeric(corrected_report$value), c(300, 80)),
  sum(collect(first)$amount) == 350,
  sum(collect(second)$amount) == 380,
  difference$counts[["changed"]] == 1
)

unlink(root, recursive = TRUE)
