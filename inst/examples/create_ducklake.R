library(tidyweave)
folder <- tempfile("my-ducklake-") # Use a durable project folder for real work.
lake <- open_lake(
  folder,
  backend = "ducklake",
  layers = c("raw", "staging", "core", "marts")
)
lake

orders <- product("orders", data.frame(id = 1:3, amount = c(100, 200, 50))) |>
  add_quality(~ amount >= 0)
first <- publish(orders, to = lake, layer = "core")
collect(first)
stopifnot(sum(collect(first)$amount) == 350)
close_lake(lake)

lake <- open_lake(folder)
lake
read_release(lake, "orders")
stopifnot(
  identical(lake$config$backend, "ducklake"),
  identical(lake$config$layers, c("raw", "staging", "core", "marts"))
)

corrected <- data.frame(id = 1:3, amount = c(100, 200, 80))
second <- publish(orders, data = corrected, to = lake, layer = "core")
collect(second)
stopifnot(
  sum(collect(second)$amount) == 380,
  sum(read_release(lake, "orders", first$release_id)$amount) == 350
)
close_lake(lake)

lake <- open_lake(folder, read_only = TRUE)
read_release(lake, "orders")
stopifnot(sum(read_release(lake, "orders")$amount) == 380)
close_lake(lake)

unlink(folder, recursive = TRUE) # Only remove this disposable tutorial folder.
