## ----setup, include=FALSE-----------------------------------------------------
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
library(lakefold)


## ----minimal------------------------------------------------------------------
orders <- data.frame(id = 1:3, amount = c(25, 75, 50))

product <- dl_product("orders") |>
  dl_add_source(orders)

result <- dl_run(product)
dl_collect(result)
stopifnot(sum(dl_collect(result)$amount) == 150)


## ----transform----------------------------------------------------------------
clean_orders <- function(data) {
  transform(data, amount = round(amount, 2))
}

product <- product |>
  dl_add_transform(clean_orders, name = "round_amount")


## ----contract-----------------------------------------------------------------
product <- product |>
  dl_add_contract(c(id = "integer", amount = "numeric"))


## ----richer-contract----------------------------------------------------------
order_contract <- dl_contract(
  columns = list(id = integer(), amount = double()),
  key = "id",
  owner = "Analytics",
  description = "One row per order"
)
product <- product |> dl_add_contract(order_contract)


## ----quality------------------------------------------------------------------
product <- product |>
  dl_add_quality(~ amount >= 0, name = "nonnegative")

result <- dl_run(product)
dl_quality(result)
stopifnot(all(dl_quality(result)$status == "passed"))


## ----warning-rule-------------------------------------------------------------
dl_rule(
  "small_amounts",
  ~ amount >= 10,
  severity = "warning",
  max_failure = 0.05
)


## ----inspect------------------------------------------------------------------
product
product |> dl_validate()
product |> dl_plan()
product |> dl_explain()


## ----publication, eval=requireNamespace("duckdb", quietly=TRUE)---------------
local({
  root <- tempfile("lakefold-guide-")
  on.exit(unlink(root, recursive = TRUE))
  first <- product |> dl_publish(to = root)
  stopifnot(sum(dl_collect(first)$amount) == 150)
  bad <- product |>
    dl_add_source(data.frame(id = c(1L, 1L), amount = c(10, -1)))
  blocked <- bad |> dl_publish(to = root, stop_on_failure = FALSE)
  stopifnot(blocked$status == "blocked")
  stopifnot(sum(dl_collect(first)$amount) == 150)
  dl_status(blocked)
})


## ----advanced, eval=requireNamespace("duckdb", quietly=TRUE) && requireNamespace("pointblank", quietly=TRUE)----
local({
  root <- tempfile("lakefold-advanced-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  source_con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(source_con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(source_con, "orders", orders)

  target <- dl_target_lake(file.path(root, "published"))
  save_metadata <- function(metadata) {
    jsonlite::write_json(
      metadata,
      file.path(root, "run.json"),
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null",
      na = "null"
    )
  }

  advanced <- dl_product("orders", code_version = "example-v1") |>
    dl_add_source(dl_source_database(source_con, table = "orders")) |>
    dl_add_transform(dl_sql(
      "SELECT id, round(amount, 2) AS amount FROM data"
    )) |>
    dl_add_contract(c(id = "integer", amount = "numeric")) |>
    dl_add_quality(dl_pointblank("amounts", function(data) {
      pointblank::create_agent(data) |>
        pointblank::col_vals_gte("amount", 0)
    })) |>
    dl_add_target(target) |>
    dl_add_catalog(save_metadata)

  result <- advanced |> dl_validate() |> dl_run()
  stopifnot(result$status == "published")
  stopifnot(file.exists(file.path(root, "run.json")))
  stopifnot(sum(dl_collect(result)$amount) == 150)
  stopifnot(DBI::dbIsValid(source_con))
  dl_status(result)
})
