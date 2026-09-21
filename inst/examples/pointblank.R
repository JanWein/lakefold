# A complete local example. Install pointblank only when you need its checks.
library(tidyweave)

if (requireNamespace("pointblank", quietly = TRUE)) {
  reserves <- data.frame(
    id = c("a", "b"),
    date = as.Date("2026-09-30"),
    reserve = c(100, 200)
  )
  schema <- tw_contract(
    columns = c(id = "character", date = "Date", reserve = "numeric"),
    key = c("id", "date")
  )
  checks <- tw_pointblank_checks(
    "business_checks",
    function(data) {
      pointblank::create_agent(
        data,
        actions = pointblank::action_levels(warn_at = 0.005, stop_at = 0.05)
      ) |>
        pointblank::col_vals_gte("reserve", 0)
    },
    policy = "agent"
  )

  result <- tw_product("reserves") |>
    tw_add_source(reserves) |>
    tw_add_contract(schema) |>
    tw_add_quality(checks) |>
    tw_run()
  print(tw_quality(result))
  print(tw_collect(result))
} else {
  message("Install optional package pointblank to run this example.")
}
