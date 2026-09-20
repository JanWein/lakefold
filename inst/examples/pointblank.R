# A complete local example. Install pointblank only when you need its checks.
library(tidyweave)

if (requireNamespace("pointblank", quietly = TRUE)) {
  reserves <- data.frame(
    id = c("a", "b"),
    date = as.Date("2026-09-30"),
    reserve = c(100, 200)
  )
  schema <- contract(
    columns = c(id = "character", date = "Date", reserve = "numeric"),
    key = c("id", "date")
  )
  checks <- pointblank_checks(
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

  result <- product("reserves") |>
    add_source(reserves) |>
    add_contract(schema) |>
    add_quality(checks) |>
    run()
  print(quality(result))
  print(collect(result))
} else {
  message("Install optional package pointblank to run this example.")
}
