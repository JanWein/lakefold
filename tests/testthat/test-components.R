test_that("DBI sources use parameters and close only factory-owned connections", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "orders", data.frame(id = 1:3))
  source <- dl_source_database(
    con,
    query = "SELECT * FROM orders WHERE id > ?",
    params = list(1L)
  )
  product <- dl_product("orders") |> dl_add_source(source)
  expect_equal(dl_collect(dl_run(product))$id, 2:3)
  expect_equal(DBI::dbIsValid(con), TRUE)
  expect_equal(
    dl_read_source(dl_source_database(
      con,
      table = DBI::Id(table = "orders")
    ))$id,
    1:3
  )
  factory_con <- NULL
  factory <- function() {
    factory_con <<- DBI::dbConnect(duckdb::duckdb())
    factory_con
  }
  source <- dl_source_database(factory, query = "SELECT 42 AS id")
  dl_check_component(source)
  expect_null(factory_con)
  expect_equal(dl_read_source(source)$id, 42L)
  expect_equal(DBI::dbIsValid(factory_con), FALSE)
})

test_that("SQL transforms work with ordinary data and reject missing infrastructure in preflight", {
  skip_if_not_installed("duckdb")
  product <- dl_product("totals") |>
    dl_add_source(data.frame(amount = c(10, 20))) |>
    dl_add_transform(dl_sql("SELECT sum(amount) AS total FROM data"))
  expect_equal(dl_collect(dl_run(product))$total, 30)
  local_mocked_bindings(need = function(package) {
    stop(paste("Install optional package:", package))
  })
  expect_snapshot(error = TRUE, dl_validate(product))
})

test_that("quality adapters fail closed on malformed evidence", {
  local_method <- function(generic, class, method) {
    table <- get(".__S3MethodsTable__.", envir = asNamespace("lakefold"))
    name <- paste(generic, class, sep = ".")
    assign(name, method, envir = table)
    withr::defer(rm(list = name, envir = table), envir = parent.frame())
  }
  rule <- dl_rule("external", ~ id > 0)
  class(rule) <- c("external_quality", "dl_rule")
  local_method("dl_run_quality", "external_quality", function(rule, data, ...) {
    data.frame(status = "passed")
  })
  product <- dl_product("orders") |>
    dl_add_source(data.frame(id = 1L)) |>
    dl_add_quality(rule)
  result <- dl_run(product, stop_on_failure = FALSE)
  expect_equal(result$status, "blocked")
  expect_equal(tail(result$quality$status, 1), "error")
})
