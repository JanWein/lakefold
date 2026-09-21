library(tidyweave)
input <- data.frame(id = 1:3, amount = c(25, 75, 50))
orders <- product("orders", input)
result <- trial(orders)
collect(result)
stopifnot(sum(collect(result)$amount) == 150)

orders <- orders |>
  dplyr::mutate(amount = round(amount, 2)) |>
  add_quality(~ amount >= 0, name = "nonnegative")
quality(trial(orders))

orders <- orders |> add_contract(c(id = "integer", amount = "numeric"))

order_contract <- contract(
  columns = list(id = integer(), amount = double()),
  key = "id"
)
orders <- orders |> add_contract(order_contract)

orders
explain(orders)
validate(orders)

bad_input <- data.frame(id = 1:2, amount = c(10, -1))
blocked <- trial(orders, data = bad_input)
quality_report(blocked)
stopifnot(blocked$status == "blocked")

customers <- data.frame(customer = c(1L, 2L), region = c("North", "South"))
sales <- data.frame(customer = c(1L, 2L), amount = c(100, 250))
regional <- product("regional_orders", sales) |>
  add_lookup(customers, by = dplyr::join_by(customer), name = "customers")
collect(trial(regional))

corrected_customers <- customers
corrected_customers$region[corrected_customers$customer == 2L] <- "North"
corrected_result <- trial(
  regional,
  sources = list(customers = corrected_customers)
)
collect(corrected_result)

summary <- product("regional_summary", regional) |>
  dplyr::summarise(total = sum(amount))
summary_result <- trial(summary)
collect(summary_result)
stopifnot(collect(summary_result)$total == 350)


evidence_path <- tempfile("orders-runs-")
result <- run(orders, evidence = evidence_path)
run_history(evidence_path)
read_run(evidence_path, result$run_id)$status
unlink(evidence_path, recursive = TRUE)
