library(dataraft.core)
family_extensions <- paste0(
  "dataraft.",
  c("lake", "adapters", "dbt", "catalog", "metrics")
)
stopifnot(!any(family_extensions %in% loadedNamespaces()))
flow <- dr_workflow() |>
  dr_add_product(
    dr_product("orders") |>
      dr_add_contract(c(id = "integer", amount = "numeric")) |>
      dr_add_quality(~ amount >= 0)
  ) |>
  dr_add_recipe(dr_recipe() |> dr_step_mutate(amount = round(amount, 2)))
bad <- dr_trial(flow, data = data.frame(id = 1:3, amount = c(25, -75, 50)))
stopifnot(identical(bad$status, "blocked"), nrow(dr_quality_rows(bad)) > 0L)
good <- dr_trial(flow, data = data.frame(id = 1:3, amount = c(25, 75, 50)))
stopifnot(sum(dr_collect(good)$amount) == 150)
stopifnot(!any(family_extensions %in% loadedNamespaces()))
cat("Independent core workflow passed.\n")
