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

payments <- tw_product("payments", payment_data) |>
  tw_add_lookup(contract_data, by = "policy_id", name = "contracts") |>
  tw_add_lookup(broker_data, by = "broker_id", name = "brokers") |>
  tw_add_contract(tw_contract(
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
  tw_add_quality(~ amount >= 0, name = "nonnegative")
payments

preview <- tw_trial(payments)
preview
tw_quality_report(preview)
tw_quality_rows(preview)
stopifnot(identical(tw_quality_rows(preview)$payment_id, "T3"))

fixed_payments <- payment_data
fixed_payments$amount[fixed_payments$payment_id == "T3"] <- 50
preview <- tw_trial(payments, sources = list(payments = fixed_payments))
tw_collect(preview)
stopifnot(sum(tw_collect(preview)$amount) == 350)

metrics <- tw_metric_set(
  "payments",
  total = sum(amount, na.rm = TRUE),
  dimensions = "company",
  units = "EUR"
)
preview_values <- tw_measure(preview, metrics = metrics, by = "company")
preview_values
stopifnot(identical(tw_collect(preview_values)$value, c(300, 50)))


root <- tempfile("tidyweave-everyday-")
payments <- payments |> tw_set_target(root)
first <- tw_publish(payments, sources = list(payments = fixed_payments))

# Only after business review: approval is your explicit declaration.
metrics <- tw_metric_set(
  "payments",
  total = sum(amount, na.rm = TRUE),
  dimensions = "company",
  units = "EUR",
  approved = TRUE,
  code_version = "payment-totals-v1"
)
values <- tw_measure(first, metrics = metrics, by = "company")
tw_report_release(values, "august-v1", code_version = "report-v1")

corrected_payments <- fixed_payments
corrected_payments$amount[corrected_payments$payment_id == "T3"] <- 80
second <- tw_publish(payments, sources = list(payments = corrected_payments))
difference <- tw_compare(first, second)
difference
difference$changed

corrected_values <- tw_measure(second, metrics = metrics, by = "company")
corrected_values
tw_report_release(corrected_values, "august-v2", code_version = "report-v1")

corrected_contracts <- contract_data
corrected_contracts$company[corrected_contracts$policy_id == "P3"] <- "North"
third <- tw_publish(
  payments,
  sources = list(
    payments = corrected_payments,
    contracts = corrected_contracts
  )
)
reference_values <- tw_measure(third, metrics = metrics, by = "company")
reference_values
stopifnot(identical(tw_collect(reference_values)$value, 380))

original_report <- tw_report_read(root, "august-v1", values_only = TRUE)
corrected_report <- tw_report_read(root, "august-v2", values_only = TRUE)
original_report
corrected_report
stopifnot(
  identical(as.numeric(original_report$value), c(300, 50)),
  identical(as.numeric(corrected_report$value), c(300, 80)),
  sum(tw_collect(first)$amount) == 350,
  sum(tw_collect(second)$amount) == 380,
  difference$counts[["changed"]] == 1
)

unlink(root, recursive = TRUE)
