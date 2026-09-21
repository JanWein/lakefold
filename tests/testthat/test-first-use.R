test_that("delivery names survive simultaneous corrections without changing definitions", {
  policies <- data.frame(policy = 1:2, company = c("North", "South"))
  brokers <- data.frame(company = c("North", "South"), channel = c("a", "b"))
  definition <- tw_product(
    "payments",
    data.frame(policy = 1:2, amount = c(10, 20))
  ) |>
    tw_add_lookup(policies, by = "policy") |>
    tw_add_lookup(brokers, by = "company") |>
    tw_add_quality(~ amount >= 0)
  original <- definition
  expect_snapshot(
    error = TRUE,
    dplyr::left_join(definition, policies, by = "policy")
  )
  expect_output(
    tw_explain(definition),
    "Deliveries: payments, policies, brokers"
  )
  changed <- tw_trial(
    definition,
    data = data.frame(policy = 1:2, amount = c(30, 40)),
    sources = list(policies = transform(policies, company = "North"))
  )
  expect_equal(tw_collect(changed)$amount, c(30, 40))
  expect_equal(tw_collect(changed)$channel, c("a", "a"))
  expect_identical(definition, original)
  expect_equal(tw_collect(tw_trial(definition))$company, c("North", "South"))
  failed <- tw_trial(
    definition,
    sources = list(policies = policies[1, , drop = FALSE])
  )
  expect_equal(tw_quality_rows(failed)$policy, 2L)
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(definition, unknown = policies)
  )
  expect_snapshot(
    error = TRUE,
    tw_trial(definition, data = policies, sources = list(payments = policies))
  )
})

test_that("lookup names can be explicit and cannot silently select another delivery", {
  definition <- tw_product("payments", data.frame(id = 1L)) |>
    tw_add_lookup(
      data.frame(id = 1L, value = 10),
      by = "id",
      name = "contracts"
    )
  expect_equal(
    tw_collect(tw_trial(
      definition,
      sources = list(contracts = data.frame(id = 1L, value = 20))
    ))$value,
    20
  )
  expect_snapshot(
    error = TRUE,
    tw_add_lookup(
      definition,
      data.frame(id = 1L),
      by = "id",
      name = "contracts"
    )
  )
  nested <- tw_product("contracts", data.frame(id = 1L, value = 30))
  ambiguous <- tw_product("payments", nested, source_name = "input") |>
    tw_add_lookup(data.frame(id = 1L), by = "id", name = "contracts")
  expect_snapshot(
    error = TRUE,
    tw_replace_sources(
      ambiguous,
      contracts = data.frame(id = 1L)
    )
  )
})

test_that("trial retains a failed result and row diagnostics select a single rule", {
  definition <- tw_product(
    "payments",
    data.frame(id = 1:3, amount = c(100, 200, -50))
  ) |>
    tw_add_quality(~ amount >= 0, name = "nonnegative")
  result <- tw_trial(definition)
  expect_identical(result$status, "blocked")
  expect_equal(tw_quality_rows(result)$id, 3L)
  expect_snapshot(error = TRUE, tw_collect(result))
  expect_snapshot(error = TRUE, tw_trial(definition, stop_on_failure = TRUE))
  definition <- tw_add_quality(definition, ~ amount < 150, name = "ceiling")
  failed <- tw_trial(definition)
  expect_snapshot(error = TRUE, tw_quality_rows(failed))
  expect_equal(tw_quality_rows(failed, "ceiling")$id, 2L)
})

test_that("a shared product keeps one delivery name and updates every reference", {
  source <- tw_product("input", data.frame(id = 1L, amount = 10))
  definition <- tw_product("joined", source) |>
    tw_add_lookup(source, by = "id")
  expect_output(tw_explain(definition), "Deliveries: input")
  result <- tw_trial(
    definition,
    sources = list(input = data.frame(id = 1L, amount = 20))
  )
  expect_equal(tw_collect(result)$amount.x, 20)
  expect_equal(tw_collect(result)$amount.y, 20)
})

test_that("overall and grouped measurements make the requested layout clear", {
  result <- tw_trial(tw_product(
    "payments",
    data.frame(company = c("North", "South"), amount = c(100, 50))
  ))
  definitions <- tw_metric_set(
    "payments",
    total = sum(amount),
    dimensions = "company"
  )
  expect_snapshot(total <- tw_measure(result, metrics = definitions))
  expect_equal(tw_collect(total)$value, 150)
  grouped <- tw_measure(result, metrics = definitions, by = "company")
  expect_equal(tw_collect(grouped)$value, c(100, 50))
  expect_snapshot(print(grouped))
  expect_snapshot(print(tw_measure(
    result,
    metrics = definitions,
    by = character()
  )))
})
