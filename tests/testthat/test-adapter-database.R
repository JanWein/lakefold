test_that("DBI targets publish safely quoted identifiers and retain caller connections", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  data <- data.frame(id = 1:2, amount = c(5, 10))
  table <- DBI::Id(table = 'orders; DROP TABLE "other"')
  target <- target_database(con, table)
  output <- write_target(target, data, list())
  expect_equal(DBI::dbReadTable(con, table), data)
  expect_equal(output$rows, 2L)
  expect_true(DBI::dbIsValid(con))
  expect_identical(inspect(target)$connection, "caller-owned")
  expect_true(is.na(capabilities(target)$transactions))
  expect_false(capabilities(target)$immutable)
})

test_that("DBI append validates the full candidate and rolls back failures", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "orders", data.frame(id = 1L))
  schema <- contract(columns = c(id = "integer"), key = "id")
  target <- target_database(con, "orders", mode = "append")
  expect_error(
    write_target(target, data.frame(id = 1L), list(contract = schema)),
    class = "tw_target_quality_failed"
  )
  expect_equal(DBI::dbReadTable(con, "orders")$id, 1L)
  output <- write_target(target, data.frame(id = 2L), list(contract = schema))
  expect_equal(output$rows, 2L)
  expect_equal(output$written_rows, 1L)
  expect_true(quality_ok(output$candidate_quality))
  expect_equal(DBI::dbReadTable(con, "orders")$id, 1:2)
  expect_error(
    write_target(target, data.frame(id = 3L), list()),
    "requires a contract"
  )
  expect_error(
    target_database(con, "orders", mode = "append", transaction = FALSE),
    "requires transaction"
  )
  DBI::dbExecute(con, "CREATE TABLE guarded (id INTEGER CHECK (id > 0))")
  DBI::dbExecute(con, "INSERT INTO guarded VALUES (1)")
  expect_error(write_target(
    target_database(con, "guarded", mode = "append"),
    data.frame(id = c(2L, -1L)),
    list(contract = schema)
  ))
  expect_equal(DBI::dbReadTable(con, "guarded")$id, 1L)
  result <- product("orders") |>
    add_source(data.frame(id = 3L)) |>
    add_contract(schema) |>
    set_target(target) |>
    run()
  expect_equal(result$outputs$rows, 3L)
  expect_equal(collect(result)$id, 3L)
  blocked <- product("orders") |>
    add_source(data.frame(id = 3L)) |>
    add_contract(schema) |>
    set_target(target) |>
    run(stop_on_failure = FALSE)
  expect_identical(blocked$status, "blocked")
  expect_false(quality_ok(blocked$quality))
  expect_equal(DBI::dbReadTable(con, "orders")$id, 1:3)
})

test_that("DuckDB targets fail closed on unsafe integer64 conversion", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("bit64")
  unsafe <- DBI::dbConnect(duckdb::duckdb())
  safe <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(unsafe, shutdown = TRUE))
  withr::defer(DBI::dbDisconnect(safe, shutdown = TRUE))
  data <- data.frame(id = bit64::as.integer64("9007199254740993"))
  expect_error(
    write_target(target_database(unsafe, "ids"), data, list()),
    "bigint = 'integer64'",
    fixed = TRUE
  )
  expect_false(DBI::dbExistsTable(unsafe, "ids"))
  write_target(target_database(safe, "ids"), data, list())
  expect_identical(
    as.character(DBI::dbReadTable(safe, "ids")$id),
    "9007199254740993"
  )
  DBI::dbExecute(unsafe, "CREATE TABLE existing_ids (id BIGINT)")
  DBI::dbExecute(unsafe, "INSERT INTO existing_ids VALUES (9007199254740993)")
  expect_error(
    write_target(
      target_database(unsafe, "existing_ids", mode = "append"),
      data.frame(id = 2),
      list(contract = contract(columns = c(id = "numeric"), key = "id"))
    ),
    "bigint = 'integer64'",
    fixed = TRUE
  )
  expect_identical(
    DBI::dbGetQuery(
      unsafe,
      "SELECT CAST(id AS VARCHAR) AS exact_id FROM existing_ids"
    )$exact_id,
    "9007199254740993"
  )
  exact <- contract(columns = c(id = "integer64"), key = "id")
  write_target(
    target_database(safe, "ids", mode = "append"),
    data.frame(id = bit64::as.integer64("9007199254740992")),
    list(contract = exact)
  )
  expect_identical(
    as.character(DBI::dbReadTable(safe, "ids")$id),
    c("9007199254740993", "9007199254740992")
  )
})

test_that("DBI stored-candidate gates roll back casts that create duplicate keys", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE cast_ids (id INTEGER)")
  DBI::dbExecute(con, "INSERT INTO cast_ids VALUES (1)")
  schema <- contract(columns = c(id = "numeric"), key = "id")
  # Both the incoming value and its uncast R candidate are valid.
  expect_true(quality_ok(validate(data.frame(id = c(1, 1.4)), schema)))
  failure <- tryCatch(
    write_target(
      target_database(con, "cast_ids", mode = "append"),
      data.frame(id = 1.4),
      list(contract = schema)
    ),
    error = identity
  )
  expect_s3_class(failure, "tw_target_quality_failed")
  expect_false(quality_ok(failure$quality))
  expect_equal(DBI::dbReadTable(con, "cast_ids")$id, 1L)
  result <- product("cast_ids") |>
    add_source(data.frame(id = 1.4)) |>
    add_contract(schema) |>
    set_target(target_database(con, "cast_ids", mode = "append")) |>
    run(stop_on_failure = FALSE)
  expect_identical(result$status, "blocked")
  expect_false(quality_ok(result$quality))
  expect_equal(DBI::dbReadTable(con, "cast_ids")$id, 1L)
})

test_that("replacement checks stored constraints and rolls back transactional DDL", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "orders", data.frame(amount = 8))
  schema <- contract(
    columns = c(amount = "numeric"),
    rules = list(quality_rule("fraction", ~ amount > 1 & amount < 2))
  )
  incoming <- data.frame(amount = 1.4)
  expect_true(quality_ok(validate(incoming, schema)))
  expect_error(
    write_target(
      target_database(con, "orders", field.types = c(amount = "INTEGER")),
      incoming,
      list(contract = schema)
    ),
    class = "tw_target_quality_failed"
  )
  expect_identical(DBI::dbReadTable(con, "orders")$amount, 8)
  schema <- contract(columns = c(amount = "numeric"))
  output <- write_target(
    target_database(con, "orders", field.types = c(amount = "INTEGER")),
    data.frame(amount = 2),
    list(contract = schema)
  )
  expect_identical(output$schema, c(amount = "integer"))
  expect_true(quality_ok(output$candidate_quality))
  expect_error(
    target_database(con, "orders", transaction = FALSE),
    "requires transaction = TRUE",
    fixed = TRUE
  )
})

test_that("DBI factory connections close after success and failure", {
  skip_if_not_installed("RSQLite")
  opened <- NULL
  factory <- function() {
    opened <<- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    opened
  }
  write_target(target_database(factory, "orders"), data.frame(id = 1L), list())
  expect_false(DBI::dbIsValid(opened))
  expect_error(
    write_target(
      target_database(factory, "orders", mode = "append"),
      data.frame(id = 1L),
      list()
    ),
    "requires a contract"
  )
  expect_false(DBI::dbIsValid(opened))
  expect_error(
    target_database(factory, "orders", overwrite = FALSE),
    "reserved"
  )
})

test_that("the same composed product exchanges DBI, Parquet and pins targets", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("arrow")
  skip_if_not_installed("pins")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  path <- withr::local_tempfile(fileext = ".parquet")
  board <- pins::board_temp(versioned = TRUE)
  definition <- product("orders") |>
    add_source(data.frame(id = 1:2, amount = c(5, 10))) |>
    add_transform(function(data) dplyr::mutate(data, amount = amount * 2)) |>
    add_contract(c(id = "integer", amount = "numeric")) |>
    add_quality(~ amount > 0)
  targets <- list(
    target_database(con, "orders"),
    target_parquet(path),
    target_pins(board, "orders")
  )
  results <- lapply(targets, function(target) {
    run(set_target(definition, target))
  })
  expected <- tibble::tibble(id = 1:2, amount = c(10, 20))
  for (result in results) {
    expect_identical(result$status, "published")
    expect_equal(collect(result), expected)
    expect_true(quality_ok(result$quality))
    expect_equal(result$metadata$rows, 2L)
  }
  sources <- list(
    source_database(con, table = "orders"),
    source_parquet(path),
    source_pins(board, "orders")
  )
  for (source in sources) {
    result <- product("readback") |>
      add_source(source) |>
      add_transform(function(data) dplyr::filter(data, id > 1L)) |>
      add_quality(~ amount > 0) |>
      run()
    expect_equal(collect(result), expected[2L, ])
  }
})
