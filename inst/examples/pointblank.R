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
    dl_pointblank("business_checks", function(data) {
      create_agent(tbl = data) |>
        col_vals_gte(columns = "reserve", value = 0) |>
        col_vals_not_null(columns = c("id", "date", "reserve"))
    })
  )
)
# The framework gate uses max_failure and severity on dl_pointblank().
# pointblank action thresholds are not the publication policy.
# Inactive/errored checks block even when their severity is warning.
