test_that("delivery names survive simultaneous corrections without changing definitions", {
  policies <- data.frame(policy = 1:2, company = c("North", "South"))
  brokers <- data.frame(company = c("North", "South"), channel = c("a", "b"))
  definition <- dr_product(
    "payments",
    data.frame(policy = 1:2, amount = c(10, 20))
  ) |>
    dr_add_lookup(policies, by = "policy") |>
    dr_add_lookup(brokers, by = "company") |>
    dr_add_quality(~ amount >= 0)
  original <- definition
  expect_snapshot(
    error = TRUE,
    dplyr::left_join(definition, policies, by = "policy")
  )
  expect_output(
    dr_explain(definition),
    "Deliveries: payments, policies, brokers"
  )
  changed <- dr_trial(
    definition,
    data = data.frame(policy = 1:2, amount = c(30, 40)),
    sources = list(policies = transform(policies, company = "North"))
  )
  expect_equal(dr_collect(changed)$amount, c(30, 40))
  expect_equal(dr_collect(changed)$channel, c("a", "a"))
  expect_identical(definition, original)
  expect_equal(dr_collect(dr_trial(definition))$company, c("North", "South"))
  failed <- dr_trial(
    definition,
    sources = list(policies = policies[1, , drop = FALSE])
  )
  expect_equal(dr_quality_rows(failed)$policy, 2L)
  expect_snapshot(
    error = TRUE,
    dr_replace_sources(definition, unknown = policies)
  )
  expect_snapshot(
    error = TRUE,
    dr_trial(definition, data = policies, sources = list(payments = policies))
  )
})

test_that("lookup names can be explicit and cannot silently select another delivery", {
  definition <- dr_product("payments", data.frame(id = 1L)) |>
    dr_add_lookup(
      data.frame(id = 1L, value = 10),
      by = "id",
      name = "contracts"
    )
  expect_equal(
    dr_collect(dr_trial(
      definition,
      sources = list(contracts = data.frame(id = 1L, value = 20))
    ))$value,
    20
  )
  expect_snapshot(
    error = TRUE,
    dr_add_lookup(
      definition,
      data.frame(id = 1L),
      by = "id",
      name = "contracts"
    )
  )
  nested <- dr_product("contracts", data.frame(id = 1L, value = 30))
  ambiguous <- dr_product("payments", nested, source_name = "input") |>
    dr_add_lookup(data.frame(id = 1L), by = "id", name = "contracts")
  expect_snapshot(
    error = TRUE,
    dr_replace_sources(
      ambiguous,
      contracts = data.frame(id = 1L)
    )
  )
})

test_that("trial retains a failed result and row diagnostics select a single rule", {
  definition <- dr_product(
    "payments",
    data.frame(id = 1:3, amount = c(100, 200, -50))
  ) |>
    dr_add_quality(~ amount >= 0, name = "nonnegative")
  result <- dr_trial(definition)
  expect_identical(result$status, "blocked")
  expect_equal(dr_quality_rows(result)$id, 3L)
  expect_snapshot(error = TRUE, dr_collect(result))
  expect_snapshot(error = TRUE, dr_trial(definition, stop_on_failure = TRUE))
  definition <- dr_add_quality(definition, ~ amount < 150, name = "ceiling")
  failed <- dr_trial(definition)
  expect_snapshot(error = TRUE, dr_quality_rows(failed))
  expect_equal(dr_quality_rows(failed, "ceiling")$id, 2L)
})

test_that("a shared product keeps one delivery name and updates every reference", {
  source <- dr_product("input", data.frame(id = 1L, amount = 10))
  definition <- dr_product("joined", source) |>
    dr_add_lookup(source, by = "id")
  expect_output(dr_explain(definition), "Deliveries: input")
  result <- dr_trial(
    definition,
    sources = list(input = data.frame(id = 1L, amount = 20))
  )
  expect_equal(dr_collect(result)$amount.x, 20)
  expect_equal(dr_collect(result)$amount.y, 20)
})

test_that("overall and grouped measurements make the requested layout clear", {
  result <- dr_trial(dr_product(
    "payments",
    data.frame(company = c("North", "South"), amount = c(100, 50))
  ))
  definitions <- dr_metric_set(
    "payments",
    total = sum(amount),
    dimensions = "company"
  )
  expect_snapshot(total <- dr_measure(result, metrics = definitions))
  expect_equal(dr_collect(total)$value, 150)
  grouped <- dr_measure(result, metrics = definitions, by = "company")
  expect_equal(dr_collect(grouped)$value, c(100, 50))
  expect_snapshot(print(grouped))
  expect_snapshot(print(dr_measure(
    result,
    metrics = definitions,
    by = character()
  )))
})
