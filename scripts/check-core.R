# Run in an installation containing only hard dependencies.
# CI deliberately omits DuckDB and every other optional integration.
stopifnot(!requireNamespace("duckdb", quietly = TRUE))
library(tidyweave)

input <- data.frame(id = 1:3, amount = c(10, 20, 30))
product <- product("orders", function() input) |>
  dplyr::mutate(amount = amount * 2) |>
  add_contract(list(id = integer(), amount = double())) |>
  add_quality(~ amount >= 0)

stopifnot(isTRUE(attr(plan(product), "complete")))
result <- product |> validate() |> run()
stopifnot(identical(result$status, "completed"))
stopifnot(identical(collect(result)$amount, c(20, 40, 60)))
stopifnot(all(quality(result)$status == "passed"))
stopifnot(length(result$metadata$rows) == 1L, result$metadata$rows == 3)
stopifnot(identical(status(result)$success, TRUE))

enriched <- product("enriched", result) |>
  add_lookup(data.frame(id = 1:3, category = c("a", "a", "b")), by = "id") |>
  dplyr::summarise(amount = sum(amount), .by = category) |>
  run()
stopifnot(identical(dplyr::collect(enriched)$amount, c(60, 60)))
stopifnot(result$run_id %in% enriched$inputs$run_id)

blocked <- product |>
  add_source(
    data.frame(id = 1L, amount = -1),
    replace = TRUE
  ) |>
  run(stop_on_failure = FALSE)
stopifnot(identical(blocked$status, "blocked"))

path <- tempfile("must-not-create-")
error <- tryCatch(publish(product, to = path), error = identity)
stopifnot(inherits(error, "error"))
stopifnot(grepl("duckdb", conditionMessage(error), fixed = TRUE))
stopifnot(!file.exists(path))
cat(
  "Core installation without DuckDB: native workflow, quality, metadata and optional target preflight passed.\n"
)
