# Run in an installation containing only hard dependencies.
# CI deliberately omits DuckDB and every other optional integration.
stopifnot(!requireNamespace("duckdb", quietly = TRUE))
library(lakefold)

input <- data.frame(id = 1:3, amount = c(10, 20, 30))
product <- dl_product("orders") |>
  dl_add_source(function() input) |>
  dl_add_transform(function(data) transform(data, amount = amount * 2)) |>
  dl_add_contract(list(id = integer(), amount = double())) |>
  dl_add_quality(~ amount >= 0)

stopifnot(isTRUE(attr(dl_plan(product), "complete")))
result <- product |> dl_validate() |> dl_run()
stopifnot(identical(result$status, "completed"))
stopifnot(identical(dl_collect(result)$amount, c(20, 40, 60)))
stopifnot(all(dl_quality(result)$status == "passed"))
stopifnot(identical(result$metadata$rows, 3L))
stopifnot(identical(dl_status(result)$success, TRUE))

blocked <- product |>
  dl_add_source(data.frame(id = 1L, amount = -1)) |>
  dl_run(stop_on_failure = FALSE)
stopifnot(identical(blocked$status, "blocked"))

path <- tempfile("must-not-create-")
error <- tryCatch(dl_publish(product, to = path), error = identity)
stopifnot(inherits(error, "error"))
stopifnot(grepl("duckdb", conditionMessage(error), fixed = TRUE))
stopifnot(!file.exists(path))
cat(
  "Core installation without DuckDB: native workflow, quality, metadata and optional target preflight passed.\n"
)
