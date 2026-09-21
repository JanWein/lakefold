library(tidyweave)

# Definitions do not read data. Execution binds the source to the workflow.
specification <- tw_product(PROJECT_PRODUCT_ID) |>
  tw_add_quality(~ amount >= 0)
preparation <- tw_recipe() |>
  tw_step_mutate(amount = amount * 2)
definition <- tw_workflow() |>
  tw_add_product(specification) |>
  tw_add_recipe(preparation) |>
  tw_add_source("data/input.csv")
