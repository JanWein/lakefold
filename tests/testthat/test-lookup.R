test_that("checked lookups preserve rows, names and groups without eager reads", {
  calls <- 0L
  reference <- function() {
    calls <<- calls + 1L
    data.frame(id = c("a", "b", "unused"), label = c("North", "South", "Other"))
  }
  input <- data.frame(customer = c("a", "a", "b"), label = c("x", "y", "z")) |>
    dplyr::group_by(customer)
  definition <- product("orders") |>
    add_source(input) |>
    add_lookup(
      reference,
      by = dplyr::join_by(customer == id),
      suffix = c("", "_region")
    )
  expect_equal(calls, 0L)
  validate(definition)
  expect_equal(calls, 0L)
  output <- run(definition) |> collect()
  expect_equal(calls, 1L)
  expect_equal(output$customer, input$customer)
  expect_equal(output$label_region, c("North", "North", "South"))
  expect_equal(output$label, c("x", "y", "z"))
  step <- definition$transforms[[1]]
  grouped <- execute_transform(
    step,
    input,
    sources = list(lookup = reference())
  )
  expect_equal(dplyr::group_vars(grouped), "customer")
})

test_that("partial key mappings support composite lookup grains", {
  input <- data.frame(id = c("p1", "p1", "p1"), month = c(1L, 1L, 2L))
  reference <- data.frame(id = c("p1", "p1"), date = 1:2, due = c(100, 200))
  result <- product("payments") |>
    add_source(input) |>
    add_lookup(reference, by = c("id", month = "date")) |>
    run() |>
    collect()
  expect_equal(result$due, c(100, 100, 200))
  expect_equal(nrow(result), 3L)
})

test_that("duplicate or missing parent keys fail before enrichment", {
  for (parent in list(
    data.frame(id = c(1L, 1L)),
    data.frame(id = c(1L, NA_integer_)),
    data.frame(id = c(1L, 9L, 9L))
  )) {
    result <- product("orders") |>
      add_source(data.frame(id = 1L)) |>
      add_lookup(parent, by = "id") |>
      run(stop_on_failure = FALSE)
    expect_identical(result$status, "error")
    expect_s3_class(result$error$parent, "tw_lookup_parent_key")
  }
})

test_that("orphan and missing child keys require an explicit keep policy", {
  input <- data.frame(id = c(1L, 2L, NA_integer_))
  parent <- data.frame(id = 1L, label = "found")
  definition <- product("orders") |> add_source(input)
  blocked <- definition |>
    add_lookup(parent, by = "id") |>
    run(stop_on_failure = FALSE)
  expect_s3_class(blocked$error$parent, "tw_lookup_unmatched")
  kept <- definition |>
    add_lookup(parent, by = "id", unmatched = "keep") |>
    run() |>
    collect()
  expect_equal(kept$label, c("found", NA_character_, NA_character_))
  expect_equal(kept$id, input$id)
})

test_that("dm and native lookups enforce the same null and cardinality policy", {
  skip_if_not_installed("dm")
  input <- data.frame(id = c("a", "a", "b"), month = c(1L, 2L, 1L))
  parent <- data.frame(
    id = c("a", "a", "b"),
    month = c(1L, 2L, 1L),
    due = c(10, 20, 30)
  )
  outputs <- lapply(c("native", "dm"), function(engine) {
    definition <- product("payments") |> add_source(input)
    output <- definition |>
      add_lookup(parent, by = c("id", "month"), engine = engine) |>
      run() |>
      collect()
    orphan <- input
    orphan$month[[1]] <- NA_integer_
    bad <- product("bad") |>
      add_source(orphan) |>
      add_lookup(parent, by = c("id", "month"), engine = engine) |>
      run(stop_on_failure = FALSE)
    expect_s3_class(bad$error$parent, "tw_lookup_unmatched")
    missing_parent <- parent
    missing_parent$id[[1]] <- NA_character_
    invalid <- definition |>
      add_lookup(
        missing_parent,
        by = c("id", "month"),
        engine = engine,
        unmatched = "keep"
      ) |>
      run(stop_on_failure = FALSE)
    expect_s3_class(invalid$error$parent, "tw_lookup_parent_key")
    duplicate <- dplyr::bind_rows(parent, parent[1, ])
    invalid <- definition |>
      add_lookup(duplicate, by = c("id", "month"), engine = engine) |>
      run(stop_on_failure = FALSE)
    expect_s3_class(invalid$error$parent, "tw_lookup_parent_key")
    output
  })
  expect_equal(outputs[[1]], outputs[[2]])
  expect_equal(outputs[[1]]$due, c(10, 20, 30))
})

test_that("lookup references can be shared product dependencies", {
  reads <- 0L
  parent <- product("customers") |>
    add_source(function() {
      reads <<- reads + 1L
      data.frame(id = 1:2, label = c("a", "b"))
    })
  definition <- product("orders") |>
    add_source(data.frame(id = c(1L, 1L))) |>
    add_lookup(parent, by = "id")
  result <- run(definition)
  expect_equal(reads, 1L)
  expect_equal(collect(result)$label, c("a", "a"))
})

test_that("lookup evidence belongs only to the step that checked the relationship", {
  result <- product("orders") |>
    add_source(data.frame(id = c(1L, 1L, 2L))) |>
    add_lookup(data.frame(id = 1:2, amount = c(10, 20)), by = "id") |>
    dplyr::mutate(amount = amount * 2) |>
    run()
  expect_named(result$metadata$transformations, "lookup_1")
  evidence <- result$metadata$transformations$lookup_1
  expect_identical(evidence$engine, "native")
  expect_identical(evidence$keys, c(id = "id"))
  expect_equal(c(evidence$input_rows, evidence$output_rows), c(3, 3))
  expect_identical(evidence$row_preserved, TRUE)
  expect_equal(
    evidence$constraints,
    list(
      parent_unique = "passed",
      parent_nonmissing = "passed",
      input_keys = "passed"
    )
  )
  expect_null(attr(result$data, "tw_transform_metadata"))
  expect_equal(collect(result)$amount, c(20, 20, 40))
})

test_that("empty inputs preserve their grain and optional missing references", {
  input <- data.frame(id = integer())
  definition <- product("empty") |>
    add_source(input) |>
    add_lookup(data.frame(id = 1L, label = "a"), by = "id") |>
    add_contract(contract(
      columns = c(id = "integer", label = "character"),
      allow_empty = TRUE
    ))
  result <- run(definition)
  expect_equal(nrow(collect(result)), 0L)
  retained <- product("orders") |>
    add_source(data.frame(id = 1L)) |>
    add_lookup(
      data.frame(id = integer(), label = character()),
      by = "id",
      unmatched = "keep"
    ) |>
    run() |>
    collect()
  expect_equal(retained$label, NA_character_)
})

test_that("lookup engine dependencies are checked before acquiring data", {
  reads <- 0L
  definition <- product("orders") |>
    add_source(function() {
      reads <<- reads + 1L
      data.frame(id = 1L)
    }) |>
    add_lookup(data.frame(id = 1L), by = "id", engine = "dm")
  local_mocked_bindings(need = function(package) {
    if (package == "dm") abort("Install optional package: dm")
  })
  error <- tryCatch(run(definition), error = identity)
  expect_s3_class(error, "tw_error")
  expect_match(
    conditionMessage(error),
    "Install optional package: dm",
    fixed = TRUE
  )
  expect_equal(reads, 0L)
})

test_that("same-database lookups remain lazy and reject implicit backend transfer", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "orders", data.frame(id = c(1L, 1L, 2L)))
  DBI::dbWriteTable(
    con,
    "customers",
    data.frame(id = 1:2, region = c("North", "South"))
  )
  input <- dplyr::tbl(con, "orders") |> dplyr::group_by(id)
  reference <- dplyr::tbl(con, "customers")
  step <- (product("orders") |> add_lookup(reference, by = "id"))$transforms[[
    1
  ]]
  joined <- execute_transform(step, input, sources = list(lookup = reference))
  expect_s3_class(joined, "tbl_sql")
  expect_equal(dplyr::group_vars(joined), "id")
  expect_equal(
    sort(dplyr::collect(joined)$region),
    c("North", "North", "South")
  )
  error <- tryCatch(
    execute_transform(
      step,
      input,
      sources = list(lookup = data.frame(id = 1L))
    ),
    error = identity
  )
  expect_s3_class(error, "tw_lookup_backend")
  if (requireNamespace("dm", quietly = TRUE)) {
    step$engine <- "dm"
    external <- execute_transform(
      step,
      input,
      sources = list(lookup = reference)
    )
    expect_s3_class(external, "tbl_sql")
    expect_equal(
      dplyr::collect(external) |> dplyr::arrange(id, region),
      dplyr::collect(joined) |> dplyr::arrange(id, region)
    )
  }
})

test_that("lookup key errors explain the equality-only boundary", {
  expect_snapshot(
    error = TRUE,
    add_lookup(
      product("orders"),
      data.frame(id = 1L),
      by = dplyr::join_by(id > id)
    )
  )
})
