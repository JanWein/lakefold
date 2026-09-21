# Run in an installation containing only hard dependencies.
# CI deliberately omits DuckDB and every other optional integration.
stopifnot(!requireNamespace("duckdb", quietly = TRUE))
library(tidyweave)

input <- data.frame(id = 1:3, amount = c(10, 20, 30))
product <- tw_product("orders", function() input) |>
  dplyr::mutate(amount = amount * 2) |>
  tw_add_contract(list(id = integer(), amount = double())) |>
  tw_add_quality(~ amount >= 0)

stopifnot(isTRUE(attr(tw_plan(product), "complete")))
result <- product |> tw_validate() |> tw_run()
stopifnot(identical(result$status, "completed"))
stopifnot(identical(tw_collect(result)$amount, c(20, 40, 60)))
stopifnot(all(tw_quality(result)$status == "passed"))
stopifnot(length(result$metadata$rows) == 1L, result$metadata$rows == 3)
stopifnot(identical(tw_status(result)$success, TRUE))

enriched <- tw_product("enriched", result) |>
  tw_add_lookup(data.frame(id = 1:3, category = c("a", "a", "b")), by = "id") |>
  dplyr::summarise(amount = sum(amount), .by = category) |>
  tw_run()
stopifnot(identical(dplyr::collect(enriched)$amount, c(60, 60)))
stopifnot(result$run_id %in% enriched$inputs$run_id)

blocked <- product |>
  tw_add_source(
    data.frame(id = 1L, amount = -1),
    replace = TRUE
  ) |>
  tw_run(stop_on_failure = FALSE)
stopifnot(identical(blocked$status, "blocked"))

execution <- tw_execution_config()
base_contract <- tw_contract(
  "core_orders",
  columns = c(id = "integer", amount = "numeric"),
  key = "id",
  rules = list(positive = ~ amount > 0)
)
enriched_contract <- tw_contract_update(
  base_contract,
  id = "core_enriched",
  columns = c(category = "character")
)
source <- tw_product("source_orders", input) |>
  tw_add_contract(base_contract)
workflow <- tw_product("core_enriched", source) |>
  tw_add_lookup(data.frame(id = 1:3, category = c("a", "a", "b")), by = "id") |>
  tw_add_contract(enriched_contract)
corrected <- workflow |>
  tw_replace_sources(
    source_orders = data.frame(id = 1:3, amount = c(5, 15, 25))
  ) |>
  tw_run(execution = execution)
stopifnot(identical(tw_collect(corrected)$amount, c(5, 15, 25)))
stopifnot(identical(
  tw_collect(tw_run(workflow, execution = execution))$amount,
  input$amount
))
stopifnot(identical(base_contract$key, enriched_contract$key))
stopifnot(all(tw_quality(corrected)$status == "passed"))

writes <- 0L
registerS3method(
  "tw_check_component",
  "tw_core_target",
  function(x, ...) invisible(x),
  envir = asNamespace("tidyweave")
)
registerS3method(
  "tw_write_target",
  "tw_core_target",
  function(target, data, context, ...) {
    writes <<- writes + 1L
    list(type = "core test")
  },
  envir = asNamespace("tidyweave")
)
guarded <- workflow |>
  tw_set_target(structure(list(), class = "tw_core_target"))
failed <- guarded |>
  tw_replace_sources(source_orders = data.frame(id = 1L, amount = -1)) |>
  tw_run(execution = execution, stop_on_failure = FALSE)
stopifnot(identical(tw_status(failed)$success, FALSE), identical(writes, 0L))
error <- tryCatch(
  tw_run(guarded, execution = list(quality = "native")),
  error = identity
)
stopifnot(inherits(error, "error"), identical(writes, 0L))

path <- tempfile("must-not-create-")
error <- tryCatch(tw_publish(product, to = path), error = identity)
stopifnot(inherits(error, "error"))
stopifnot(grepl("duckdb", conditionMessage(error), fixed = TRUE))
stopifnot(!file.exists(path))
cat(
  "Core installation without DuckDB: native workflows, execution defaults, contracts, corrections and publication gates passed.\n"
)

preparation <- tw_recipe() |> tw_step_mutate(amount = amount * 2)
modular <- tw_workflow() |>
  tw_add_product(tw_product("core_modular") |> tw_add_quality(~ amount > 0)) |>
  tw_add_recipe(preparation)
checked <- tw_trial(modular, data = data.frame(amount = c(10, 20)))
stopifnot(identical(tw_collect(checked)$amount, c(20, 40)))
stopifnot(identical(tw_extract_recipe(modular), preparation))
stopifnot(identical(
  tw_trial(modular, data = data.frame(amount = -1))$status,
  "blocked"
))
cat(
  "Modular specifications, recipes and workflows passed without optional engines.\n"
)
