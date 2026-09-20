library(tidyweave)
input <- data.frame(id = 1:3, amount = c(25, 75, 50))
orders <- product("orders") |> add_source(input, name = "delivery")
result <- run(orders)
collect(result)
stopifnot(sum(collect(result)$amount) == 150)

orders <- orders |>
  add_transform(function(data) transform(data, amount = round(amount, 2))) |>
  add_quality(~ amount >= 0, name = "nonnegative")
quality(run(orders))

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
bad_orders <- orders |>
  add_source(bad_input, name = "delivery", replace = TRUE)
blocked <- run(bad_orders, stop_on_failure = FALSE)
incidents(blocked)
stopifnot(blocked$status == "blocked")

customers <- data.frame(customer = c(1L, 2L), region = c("North", "South"))
sales <- data.frame(customer = c(1L, 2L), amount = c(100, 250))
regional <- product("regional_orders") |>
  add_source(sales, name = "orders") |>
  add_source(customers, name = "customers") |>
  add_transform(function(inputs) {
    dplyr::left_join(inputs$orders, inputs$customers, by = "customer")
  }) |>
  add_quality(~ !is.na(region))
collect(run(regional))

summary <- product("regional_summary") |>
  add_source(regional) |>
  add_transform(function(data) {
    dplyr::summarise(data, total = sum(amount))
  })
summary_result <- run(summary)
collect(summary_result)
stopifnot(collect(summary_result)$total == 350)


evidence_path <- tempfile("orders-runs-")
result <- run(orders, evidence = evidence_path)
run_history(evidence_path)
read_run(evidence_path, result$run_id)$status
unlink(evidence_path, recursive = TRUE)
