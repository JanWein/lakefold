library(tidyweave)
folder <- tempfile("my-ducklake-") # Use a durable project folder for real work.
lake <- tw_open_lake(
  folder,
  backend = "ducklake",
  layers = c("raw", "staging", "core", "marts")
)
lake

orders <- tw_product(
  "orders",
  data.frame(id = 1:3, amount = c(100, 200, 50))
) |>
  tw_add_quality(~ amount >= 0)
first <- tw_publish(orders, to = lake, layer = "core")
tw_collect(first)
stopifnot(sum(tw_collect(first)$amount) == 350)
tw_close_lake(lake)

lake <- tw_open_lake(folder)
lake
tw_read_release(lake, "orders")
stopifnot(
  identical(lake$config$backend, "ducklake"),
  identical(lake$config$layers, c("raw", "staging", "core", "marts"))
)

corrected <- data.frame(id = 1:3, amount = c(100, 200, 80))
second <- tw_publish(orders, data = corrected, to = lake, layer = "core")
tw_collect(second)
stopifnot(
  sum(tw_collect(second)$amount) == 380,
  sum(tw_read_release(lake, "orders", first$release_id)$amount) == 350
)
tw_close_lake(lake)

lake <- tw_open_lake(folder, read_only = TRUE)
tw_read_release(lake, "orders")
stopifnot(sum(tw_read_release(lake, "orders")$amount) == 380)
tw_close_lake(lake)

unlink(folder, recursive = TRUE) # Only remove this disposable tutorial folder.
