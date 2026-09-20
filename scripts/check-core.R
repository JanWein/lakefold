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

execution <- execution_config()
base_contract <- contract(
  "core_orders",
  columns = c(id = "integer", amount = "numeric"),
  key = "id",
  rules = list(positive = ~ amount > 0)
)
enriched_contract <- contract_update(
  base_contract,
  id = "core_enriched",
  columns = c(category = "character")
)
source <- product("source_orders", input) |>
  add_contract(base_contract)
workflow <- product("core_enriched", source) |>
  add_lookup(data.frame(id = 1:3, category = c("a", "a", "b")), by = "id") |>
  add_contract(enriched_contract)
corrected <- workflow |>
  replace_sources(
    source_orders = data.frame(id = 1:3, amount = c(5, 15, 25))
  ) |>
  run(execution = execution)
stopifnot(identical(collect(corrected)$amount, c(5, 15, 25)))
stopifnot(identical(
  collect(run(workflow, execution = execution))$amount,
  input$amount
))
stopifnot(identical(base_contract$key, enriched_contract$key))
stopifnot(all(quality(corrected)$status == "passed"))

writes <- 0L
registerS3method(
  "check_component",
  "tw_core_target",
  function(x, ...) invisible(x),
  envir = asNamespace("tidyweave")
)
registerS3method(
  "write_target",
  "tw_core_target",
  function(target, data, context, ...) {
    writes <<- writes + 1L
    list(type = "core test")
  },
  envir = asNamespace("tidyweave")
)
guarded <- workflow |>
  set_target(structure(list(), class = "tw_core_target"))
failed <- guarded |>
  replace_sources(source_orders = data.frame(id = 1L, amount = -1)) |>
  run(execution = execution, stop_on_failure = FALSE)
stopifnot(identical(status(failed)$success, FALSE), identical(writes, 0L))
error <- tryCatch(
  run(guarded, execution = list(quality = "native")),
  error = identity
)
stopifnot(inherits(error, "error"), identical(writes, 0L))

path <- tempfile("must-not-create-")
error <- tryCatch(publish(product, to = path), error = identity)
stopifnot(inherits(error, "error"))
stopifnot(grepl("duckdb", conditionMessage(error), fixed = TRUE))
stopifnot(!file.exists(path))
cat(
  "Core installation without DuckDB: native workflows, execution defaults, contracts, corrections and publication gates passed.\n"
)
