test_that("dplyr product verbs defer data and expressions until execution", {
  calls <- 0L
  x <- product("orders", function() {
    calls <<- calls + 1L
    data.frame(id = 1:3, amount = c(10, 20, 30))
  }) |>
    dplyr::mutate(
      net = {
        calls <<- calls + 1L
        amount * 2
      },
      .keep = "all"
    ) |>
    dplyr::filter(net > 20) |>
    dplyr::rename(total = net) |>
    dplyr::relocate(total, .before = id) |>
    dplyr::select(total, id) |>
    dplyr::arrange(dplyr::desc(total))
  expect_s3_class(x, "tw_product")
  expect_silent(validate(x))
  expect_length(inspect(x)$transforms, 6L)
  expect_output(print(x), "Transformations: 6")
  expect_equal(calls, 0L)
  expect_equal(
    dplyr::collect(run(x)),
    tibble::tibble(total = c(60, 40), id = c(3L, 2L))
  )
  expect_equal(calls, 2L)
  letters <- data.frame(label = c("z", "a", "B"))
  sorted <- product("sorted", letters) |> dplyr::arrange(label, .locale = "C")
  expect_equal(
    collect(run(sorted))$label,
    dplyr::arrange(letters, label, .locale = "C")$label
  )
})

test_that("captured data masking, selection and names retain dplyr semantics", {
  make <- function(multiplier, threshold) {
    product("orders", data.frame(id = 1:3, amount = c(10, 20, 30))) |>
      dplyr::mutate(dplyr::across(amount, ~ .x * .env$multiplier)) |>
      dplyr::filter(amount > .env$threshold) |>
      dplyr::select(dplyr::all_of(c("id", "amount")))
  }
  expect_equal(dplyr::collect(run(make(2, 25)))$amount, c(40, 60))
  base <- product("orders", data.frame(amount = 1))
  a <- base |> dplyr::mutate(first = amount + 1)
  b <- base |> dplyr::mutate(second = amount + 1)
  c <- base |> dplyr::mutate(first = amount + 2)
  expect_false(identical(fingerprint(inspect(a)), fingerprint(inspect(b))))
  expect_false(identical(fingerprint(inspect(a)), fingerprint(inspect(c))))
  expect_false(grepl(
    "multiplier = 2",
    jencode(inspect(make(2, 25))),
    fixed = TRUE
  ))
})

test_that("grouping, count and distinct pass options through at execution", {
  data <- data.frame(group = c("a", "a", "b"), value = c(1, 2, 4))
  group <- product("grouped", data) |>
    dplyr::group_by(group, .add = FALSE, .drop = FALSE) |>
    dplyr::summarise(total = sum(value), .groups = "drop") |>
    dplyr::arrange(group, .by_group = TRUE)
  expected <- data |>
    dplyr::group_by(group, .add = FALSE, .drop = FALSE) |>
    dplyr::summarise(total = sum(value), .groups = "drop")
  expect_equal(dplyr::collect(run(group)), expected)
  by <- product("by", data) |>
    dplyr::summarise(total = sum(value), .by = group)
  expect_equal(dplyr::collect(run(by)), expected)
  counted <- product("counts", data) |>
    dplyr::count(group, wt = value, sort = TRUE, name = "total")
  expect_equal(
    dplyr::collect(run(counted)),
    tibble::as_tibble(dplyr::count(
      data,
      group,
      wt = value,
      sort = TRUE,
      name = "total"
    ))
  )
  levels <- data.frame(group = factor("a", levels = c("a", "b")))
  dropped <- product("levels", levels) |> dplyr::count(group, .drop = FALSE)
  expect_equal(
    collect(run(dropped)),
    tibble::as_tibble(dplyr::count(levels, group, .drop = FALSE))
  )
  distinct <- product("distinct", data) |>
    dplyr::group_by(group) |>
    dplyr::ungroup() |>
    dplyr::distinct(group, .keep_all = TRUE)
  expect_equal(
    dplyr::collect(run(distinct)),
    tibble::as_tibble(dplyr::distinct(data, group, .keep_all = TRUE))
  )
})

test_that("successful results normalize without reruns and preserve provenance", {
  first <- run(product("input", data.frame(id = 1:2)))
  next_product <- product("copy", first) |> dplyr::mutate(doubled = id * 2)
  next_result <- run(next_product)
  expect_equal(dplyr::collect(next_result)$doubled, c(2, 4))
  expect_equal(next_result$inputs$asset, "input")
  expect_equal(next_result$inputs$run_id, first$run_id)
  failed <- run(
    product("failed", data.frame(id = 1L)) |>
      add_quality(~ id < 0),
    stop_on_failure = FALSE
  )
  expect_error(product("copy", failed), "successful run")
  expect_equal(dplyr::collect(first), collect(first))
  expect_identical(collect, dplyr::collect)
  expect_identical(explain, dplyr::explain)
  expect_identical(tbl, dplyr::tbl)
  expect_output(dplyr::explain(next_product), "Product: copy")
  replacement <- next_product |> add_source(data.frame(id = 3L), replace = TRUE)
  expect_equal(collect(run(replacement))$doubled, 6)
})

test_that("auxiliary products do not turn the primary dplyr input into a list", {
  calls <- 0L
  source <- product("input", function() {
    calls <<- calls + 1L
    data.frame(id = 1:2, amount = c(10, 20))
  })
  x <- product("joined", source) |>
    dplyr::filter(id == 2L) |>
    add_lookup(source, by = "id") |>
    dplyr::mutate(total = amount.x + amount.y)
  expect_silent(validate(x))
  expect_equal(calls, 0L)
  expect_equal(sum(plan(x)$step == "read"), 2L)
  result <- run(x)
  expect_equal(collect(result)$total, 40)
  expect_equal(calls, 1L)
  expect_equal(nrow(result$inputs), 2L)
  expect_length(unique(result$inputs$run_id), 1L)
  conflicting <- source |> dplyr::mutate(amount = amount + 1)
  expect_error(
    validate(
      product("bad", source) |>
        add_lookup(conflicting, by = "id")
    ),
    class = "tw_dependency_conflict"
  )
})

test_that("dplyr operations work on caller-owned lazy tables", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  data <- data.frame(group = c("a", "a", "b"), amount = c(10, 20, 30))
  DBI::dbWriteTable(con, "orders", data)
  make <- function(source) {
    product("summary", source) |>
      dplyr::filter(amount >= 20) |>
      dplyr::group_by(group) |>
      dplyr::summarise(total = sum(amount, na.rm = TRUE), .groups = "drop")
  }
  lazy <- run(make(source_database(con, "orders")))
  expect_s3_class(lazy$data, "tbl_sql")
  expect_equal(collect(lazy), collect(run(make(data))))
  expect_true(DBI::dbIsValid(con))
})

test_that("file transformations and accepted lake sources retain exact releases", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  path <- file.path(root, "orders.csv")
  utils::write.csv(
    data.frame(id = 1:2, amount = c(10, 20)),
    path,
    row.names = FALSE
  )
  lake <- open_lake(file.path(root, "lake"))
  withr::defer(close_lake(lake))
  definition <- product("orders", path) |> dplyr::mutate(amount = amount * 2)
  first <- publish(definition, to = lake, layer = "validated")
  expect_equal(collect(first)$amount, c(20, 40))
  expect_equal(
    dplyr::collect(dplyr::tbl(lake, "orders", first$release_id))$amount,
    c(20, 40)
  )
  pinned <- product("copy", first)
  utils::write.csv(
    data.frame(id = 1:2, amount = c(30, 40)),
    path,
    row.names = FALSE
  )
  later <- publish(definition, to = lake)
  copied <- publish(pinned, to = lake)
  expect_equal(collect(copied)$amount, c(20, 40))
  expect_false(identical(first$release_id, later$release_id))
  expect_true(first$release_id %in% copied$inputs$source_version)
  expect_true(first$release_id %in% copied$metadata$lineage$from_version)
  expect_true(DBI::dbIsValid(lake$con))
})

test_that("lookup contents participate in lake cache identity without changing definitions", {
  skip_if_not_installed("duckdb")
  lake <- open_lake(withr::local_tempdir())
  withr::defer(close_lake(lake))
  make <- function(reference) {
    product(
      "lookup_cache",
      data.frame(id = 1L),
      version = "1",
      code_version = "v1"
    ) |>
      add_lookup(reference, by = "id") |>
      set_target(lake)
  }
  first <- run(make(data.frame(id = 1L, amount = 10)), cache = TRUE)
  cached <- run(make(data.frame(id = 1L, amount = 10)), cache = TRUE)
  changed <- run(make(data.frame(id = 1:2, amount = c(20, 30))), cache = TRUE)
  expect_identical(cached$release_id, first$release_id)
  expect_equal(cached$status, "cached")
  expect_false(identical(changed$release_id, first$release_id))
  expect_equal(collect(changed)$amount, 20)
  definitions <- registry(lake, "assets")
  expect_equal(
    sum(
      definitions$id == "lookup_cache" &
        definitions$kind == "composed_product"
    ),
    1L
  )
})
