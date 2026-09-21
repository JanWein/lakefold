library(tidyweave)
input <- data.frame(id = 1:3, amount = c(25, 75, 50))
orders <- tw_product("orders", input)
result <- tw_trial(orders)
tw_collect(result)
stopifnot(sum(tw_collect(result)$amount) == 150)

orders <- orders |>
  dplyr::mutate(amount = round(amount, 2)) |>
  tw_add_quality(~ amount >= 0, name = "nonnegative")
tw_quality(tw_trial(orders))

orders <- orders |> tw_add_contract(c(id = "integer", amount = "numeric"))

order_contract <- tw_contract(
  columns = list(id = integer(), amount = double()),
  key = "id"
)
orders <- orders |> tw_add_contract(order_contract)

orders
tw_explain(orders)
tw_validate(orders)

bad_input <- data.frame(id = 1:2, amount = c(10, -1))
blocked <- tw_trial(orders, data = bad_input)
tw_quality_report(blocked)
stopifnot(blocked$status == "blocked")

customers <- data.frame(customer = c(1L, 2L), region = c("North", "South"))
sales <- data.frame(customer = c(1L, 2L), amount = c(100, 250))
regional <- tw_product("regional_orders", sales) |>
  tw_add_lookup(customers, by = dplyr::join_by(customer), name = "customers")
tw_collect(tw_trial(regional))

corrected_customers <- customers
corrected_customers$region[corrected_customers$customer == 2L] <- "North"
corrected_result <- tw_trial(
  regional,
  sources = list(customers = corrected_customers)
)
tw_collect(corrected_result)

summary <- tw_product("regional_summary", regional) |>
  dplyr::summarise(total = sum(amount))
summary_result <- tw_trial(summary)
tw_collect(summary_result)
stopifnot(tw_collect(summary_result)$total == 350)


evidence_path <- tempfile("orders-runs-")
result <- tw_run(orders, evidence = evidence_path)
tw_run_history(evidence_path)
tw_read_run(evidence_path, result$run_id)$status
unlink(evidence_path, recursive = TRUE)
