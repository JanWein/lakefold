library(tidyweave)

# Nothing is read or executed while this definition is created.
definition <- product(PROJECT_PRODUCT_ID) |>
  add_source("data/input.csv") |>
  add_transform(function(data) transform(data, amount = amount * 2)) |>
  add_quality(~ amount >= 0)
