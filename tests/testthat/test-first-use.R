test_that("delivery names survive simultaneous corrections without changing definitions", {
  policies <- data.frame(policy = 1:2, company = c("North", "South"))
  brokers <- data.frame(company = c("North", "South"), channel = c("a", "b"))
  definition <- product(
    "payments",
    data.frame(policy = 1:2, amount = c(10, 20))
  ) |>
    add_lookup(policies, by = "policy") |>
    add_lookup(brokers, by = "company") |>
    add_quality(~ amount >= 0)
  original <- definition
  expect_snapshot(
    error = TRUE,
    dplyr::left_join(definition, policies, by = "policy")
  )
  expect_output(explain(definition), "Deliveries: payments, policies, brokers")
  changed <- trial(
    definition,
    data = data.frame(policy = 1:2, amount = c(30, 40)),
    sources = list(policies = transform(policies, company = "North"))
  )
  expect_equal(collect(changed)$amount, c(30, 40))
  expect_equal(collect(changed)$channel, c("a", "a"))
  expect_identical(definition, original)
  expect_equal(collect(trial(definition))$company, c("North", "South"))
  failed <- trial(
    definition,
    sources = list(policies = policies[1, , drop = FALSE])
  )
  expect_equal(quality_rows(failed)$policy, 2L)
  expect_snapshot(error = TRUE, replace_sources(definition, unknown = policies))
  expect_snapshot(
    error = TRUE,
    trial(definition, data = policies, sources = list(payments = policies))
  )
})

test_that("lookup names can be explicit and cannot silently select another delivery", {
  definition <- product("payments", data.frame(id = 1L)) |>
    add_lookup(data.frame(id = 1L, value = 10), by = "id", name = "contracts")
  expect_equal(
    collect(trial(
      definition,
      sources = list(contracts = data.frame(id = 1L, value = 20))
    ))$value,
    20
  )
  expect_snapshot(
    error = TRUE,
    add_lookup(definition, data.frame(id = 1L), by = "id", name = "contracts")
  )
  nested <- product("contracts", data.frame(id = 1L, value = 30))
  ambiguous <- product("payments", nested, source_name = "input") |>
    add_lookup(data.frame(id = 1L), by = "id", name = "contracts")
  expect_snapshot(
    error = TRUE,
    replace_sources(
      ambiguous,
      contracts = data.frame(id = 1L)
    )
  )
})

test_that("trial retains a failed result and row diagnostics select a single rule", {
  definition <- product(
    "payments",
    data.frame(id = 1:3, amount = c(100, 200, -50))
  ) |>
    add_quality(~ amount >= 0, name = "nonnegative")
  result <- trial(definition)
  expect_identical(result$status, "blocked")
  expect_equal(quality_rows(result)$id, 3L)
  expect_snapshot(error = TRUE, collect(result))
  expect_snapshot(error = TRUE, trial(definition, stop_on_failure = TRUE))
  definition <- add_quality(definition, ~ amount < 150, name = "ceiling")
  failed <- trial(definition)
  expect_snapshot(error = TRUE, quality_rows(failed))
  expect_equal(quality_rows(failed, "ceiling")$id, 2L)
})

test_that("a shared product keeps one delivery name and updates every reference", {
  source <- product("input", data.frame(id = 1L, amount = 10))
  definition <- product("joined", source) |>
    add_lookup(source, by = "id")
  expect_output(explain(definition), "Deliveries: input")
  result <- trial(
    definition,
    sources = list(input = data.frame(id = 1L, amount = 20))
  )
  expect_equal(collect(result)$amount.x, 20)
  expect_equal(collect(result)$amount.y, 20)
})

test_that("overall and grouped measurements make the requested layout clear", {
  result <- trial(product(
    "payments",
    data.frame(company = c("North", "South"), amount = c(100, 50))
  ))
  definitions <- metric_set(
    "payments",
    total = sum(amount),
    dimensions = "company"
  )
  expect_snapshot(total <- measure(result, metrics = definitions))
  expect_equal(collect(total)$value, 150)
  grouped <- measure(result, metrics = definitions, by = "company")
  expect_equal(collect(grouped)$value, c(100, 50))
  expect_snapshot(print(grouped))
  expect_snapshot(print(measure(
    result,
    metrics = definitions,
    by = character()
  )))
})
