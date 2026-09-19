library(lakefold)
library(pointblank)

contract <- dl_contract(
  "risk.reserves",
  "1.0.0",
  owner = "Risk",
  description = "Validated reserves",
  grain = "One contract per business date",
  columns = c(id = "character", date = "Date", reserve = "numeric"),
  key = c("id", "date"),
  rules = list(
    dl_pointblank(
      "business_checks",
      function(data) {
        create_agent(
          tbl = data,
          actions = action_levels(warn_at = 0.005, stop_at = 0.05)
        ) |>
          col_vals_gte(columns = "reserve", value = 0) |>
          col_vals_not_null(columns = c("id", "date", "reserve"))
      },
      policy = "agent"
    )
  )
)
# Native pointblank action levels determine the gate for policy = "agent".
# Inactive/errored checks always block; no failing rows are silently removed.
# Use input_contract = contract in dl_ingest() to check before Raw writes.
# dl_validate(data, contract, keep_agents = TRUE) retains native report agents.
