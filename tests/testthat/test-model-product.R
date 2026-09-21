model_fixture <- function() {
  dm::dm(
    customers = data.frame(id = 1:2),
    policies = data.frame(policy = 1:2, id = 1:2, amount = c(10, 20))
  ) |>
    dm::dm_add_pk(customers, id) |>
    dm::dm_add_pk(policies, policy) |>
    dm::dm_add_fk(policies, id, customers)
}

test_that("models reuse contracts and diagnose a named table", {
  skip_if_not_installed("dm")
  spec <- product(
    "portfolio",
    model_fixture(),
    contracts = list(
      policies = contract(
        columns = c(policy = "integer", id = "integer", amount = "numeric"),
        key = "policy",
        rules = list(positive = ~ amount >= 0)
      )
    )
  )
  good <- trial(spec)
  expect_s3_class(collect(good), "dm")
  bad <- trial(
    spec,
    sources = list(
      policies = data.frame(policy = 1:2, id = 1:2, amount = c(-1, 20))
    )
  )
  expect_identical(bad$status, "blocked")
  expect_equal(quality_rows(bad)$policy, 1L)
  expect_equal(quality_rows(bad, "policies/positive")$amount, -1)
  expect_equal(collect(trial(spec))$policies$amount, c(10, 20))
  orphan <- trial(spec, sources = list(customers = data.frame(id = 1L)))
  expect_identical(orphan$status, "blocked")
  expect_equal(tail(quality(orphan)$status, 1), "failed")
})

test_that("model publication pins all members and rejects stale correction", {
  skip_if_not_installed("dm")
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  initialized <- open_lake(
    root,
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  close_lake(initialized)
  spec <- product("portfolio", model_fixture())
  first <- publish(spec, to = root)
  second <- publish(
    spec,
    to = root,
    previous = first,
    sources = list(
      policies = data.frame(policy = 1:2, id = 2:1, amount = c(30, 40))
    )
  )
  expect_equal(collect(first)$policies$amount, c(10, 20))
  expect_equal(collect(second)$policies$amount, c(30, 40))
  expect_equal(
    collect(trial(product("selected", first, table = "policies")))$amount,
    c(10, 20)
  )
  error <- tryCatch(
    publish(spec, to = root, previous = first),
    error = identity
  )
  expect_s3_class(error, "tw_publication_conflict")
  blocked <- publish(
    spec,
    to = root,
    sources = list(customers = data.frame(id = 1L)),
    stop_on_failure = FALSE
  )
  expect_identical(blocked$status, "blocked")
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  expect_equal(read_release(lake, "portfolio")$policies$amount, c(30, 40))
  expect_equal(nrow(releases(lake, "portfolio")), 2L)
  expect_equal(
    all(
      quality(lake, asset = "portfolio", release = first$release_id)$status ==
        "passed"
    ),
    TRUE
  )
})

test_that("a failed multi-table transaction leaves no partial release", {
  skip_if_not_installed("dm")
  skip_if_not_installed("duckdb")
  lake <- open_lake(
    withr::local_tempdir(),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(close_lake(lake))
  spec <- product("portfolio", model_fixture())
  first <- publish(spec, to = lake)
  before <- releases(lake)
  real_insert <- insert_meta
  local_mocked_bindings(insert_meta = function(lake, name, values) {
    if (name == "releases" && identical(values$asset, "portfolio.policies")) {
      stop("injected failure")
    }
    real_insert(lake, name, values)
  })
  error <- tryCatch(
    publish(spec, to = lake, previous = first),
    error = identity
  )
  expect_match(conditionMessage(error), "injected failure")
  expect_equal(releases(lake), before)
  expect_equal(collect(first)$policies$amount, c(10, 20))
})

test_that("table publication rejects a stale prior result", {
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  initialized <- open_lake(
    root,
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  close_lake(initialized)
  spec <- product("orders", data.frame(id = 1L))
  first <- publish(spec, to = root)
  second <- publish(
    spec,
    to = root,
    previous = first,
    data = data.frame(id = 2L)
  )
  error <- tryCatch(
    publish(spec, to = root, previous = first),
    error = identity
  )
  expect_s3_class(error$result$error, "tw_publication_conflict")
  expect_equal(collect(second)$id, 2L)
})

test_that("model member names and established contracts cannot be bypassed", {
  skip_if_not_installed("dm")
  skip_if_not_installed("duckdb")
  lake <- open_lake(
    withr::local_tempdir(),
    backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")
  )
  withr::defer(close_lake(lake))
  spec <- product(
    "portfolio",
    model_fixture(),
    contracts = list(
      customers = contract(columns = c(id = "integer"), key = "id")
    )
  )
  first <- publish(spec, to = lake)
  error <- tryCatch(
    publish(product("portfolio", model_fixture()), to = lake),
    error = identity
  )
  expect_match(conditionMessage(error), "Keep the explicit contract")
  error <- tryCatch(
    write_data(lake, data.frame(id = 9L), "portfolio.customers"),
    error = identity
  )
  expect_match(conditionMessage(error), "model product")
  expect_equal(collect(first)$customers$id, 1:2)
})

test_that("nested member selections reuse the active publication connection", {
  skip_if_not_installed("dm")
  skip_if_not_installed("duckdb")
  root <- withr::local_tempdir()
  first <- publish(product("portfolio", model_fixture()), to = root)
  lake <- open_lake(root)
  withr::defer(close_lake(lake))
  real_connect <- connect_lake
  local_mocked_bindings(connect_lake = function(
    config,
    read_only = config$read_only
  ) {
    if (isTRUE(read_only)) {
      stop("Unexpected second read-only attachment")
    }
    real_connect(config, read_only = read_only)
  })
  selected <- product("summary", first, table = "policies") |>
    add_lookup(product("lookup", first, table = "customers"), by = "id")
  out <- publish(selected, to = lake)
  expect_equal(collect(out)$amount, c(10, 20))
})
