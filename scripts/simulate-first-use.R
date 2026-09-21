# Run with the installed package, from the repository root.
# The tutorial is the sole source of the ordinary user journey.
library(tidyweave)
stopifnot(requireNamespace("duckdb", quietly = TRUE))
source(
  "inst/examples/everyday_workflows.R",
  echo = TRUE,
  max.deparse.length = Inf
)

# Transfer the learned operation to a different delivery.
corrected_brokers <- broker_data
corrected_brokers$channel[corrected_brokers$broker_id == "B2"] <- "Partner"
preview <- tw_trial(
  payments,
  sources = list(
    payments = corrected_payments,
    brokers = corrected_brokers
  )
)
stopifnot(identical(
  tw_collect(preview)$channel,
  c("Broker", "Broker", "Partner")
))

# A missing reference must be diagnosable through the same public operation.
missing_contract <- tw_trial(
  payments,
  sources = list(
    payments = corrected_payments,
    contracts = contract_data[1:2, ]
  )
)
stopifnot(identical(tw_quality_rows(missing_contract)$payment_id, "T3"))

# A duplicate payment is a different rule, but uses the same diagnosis.
duplicate <- tw_trial(
  payments,
  sources = list(
    payments = rbind(fixed_payments, fixed_payments[3, ])
  )
)
stopifnot(identical(tw_quality_rows(duplicate)$payment_id, c("T3", "T3")))

# Deliberate wrong turns must explain the next public operation.
unknown <- tryCatch(
  tw_trial(payments, sources = list(typo = contract_data)),
  error = identity
)
stopifnot(
  inherits(unknown, "error"),
  grepl(
    "Available names: brokers, contracts, payments",
    conditionMessage(unknown),
    fixed = TRUE
  ),
  !grepl("transform:", conditionMessage(unknown), fixed = TRUE)
)
missing_evidence <- tryCatch(
  tw_report_release(tw_collect(preview_values), "bad", code_version = "v1"),
  error = identity
)
stopifnot(
  inherits(missing_evidence, "error"),
  grepl("before tw_collect()", conditionMessage(missing_evidence), fixed = TRUE)
)

cat(
  "\nPASS: named deliveries, row diagnosis, grouped reports, corrections, immutable history and transfer cases.\n"
)
