test_that("contract composition preserves identity choices and optional columns", {
  old <- dr_contract(
    "orders",
    columns = c(id = "integer"),
    key = "id",
    owner = "Finance",
    operator = "Platform",
    column_metadata = list(id = list(description = "Order identifier"))
  )
  original <- old
  new <- dr_contract_update(
    old,
    id = "enriched",
    columns = list(channel = character())
  )
  expect_identical(new$columns, list(id = "integer", channel = "character"))
  expect_identical(new$required, "id")
  expect_identical(new$key, "id")
  expect_identical(new$owner, "Finance")
  expect_identical(new$operator, "Platform")
  expect_identical(new$column_metadata, old$column_metadata)
  expect_identical(old, original)
  revised <- dr_contract_update(old, version = "2", description = "Revised")
  expect_identical(revised$id, old$id)
  expect_identical(revised$version, "2")
  expect_identical(revised$description, "Revised")
})

test_that("contracts and product rules use the same normalization without evaluation", {
  checks <- list(nonnegative = ~ amount >= 0, opaque = function(data) {
    stop("Do not execute while defining")
  })
  definition <- dr_contract(
    "amounts",
    columns = c(amount = "numeric"),
    rules = checks
  )
  p <- dr_add_quality(dr_product("amounts"), checks)
  expect_identical(definition$rules, p$quality)
  expect_identical(
    dr_contract(columns = c(amount = "numeric"), rules = ~ amount > 0)$rules[[
      1
    ]]$name,
    "quality_1"
  )
  reused <- dr_quality_rule("old_name", ~ amount > 0, engine = "native")
  normalized <- dr_contract(
    columns = c(amount = "numeric"),
    rules = list(positive = reused)
  )$rules[[1]]
  expect_identical(normalized$name, "positive")
  expect_identical(normalized$engine_explicit, TRUE)
  expect_identical(definition$rules[[1]]$engine_explicit, FALSE)
  expect_identical(
    dr_contract_update(definition, id = "copy")$rules,
    definition$rules
  )
})

test_that("reviewed removal and aggregation replace guarantees explicitly", {
  old <- dr_contract(
    "orders",
    grain = "One order",
    columns = c(id = "integer", amount = "numeric"),
    key = "id",
    rules = list(positive = ~ amount > 0),
    column_metadata = list(id = list(description = "Identifier"))
  )
  new <- dr_contract_update(
    old,
    id = "totals",
    remove = "id",
    columns = c(total = "numeric"),
    grain = "One total",
    required = "total",
    key = character(),
    rules = list(positive = ~ total > 0)
  )
  expect_identical(new$key, character())
  expect_identical(new$required, "total")
  expect_null(new$column_metadata)
  expect_identical(new$grain, "One total")
  expect_identical(names(new$columns), c("amount", "total"))
  expect_identical(all.vars(new$rules[[1]]$check), "total")
  changed <- dr_contract_update(
    old,
    version = "2",
    columns = c(id = "character"),
    key = "id",
    rules = old$rules
  )
  expect_identical(changed$columns$id, "character")
})

test_that("unsafe inheritance and unchanged identity have actionable errors", {
  old <- dr_contract(
    "orders",
    grain = "One order",
    columns = c(id = "integer", amount = "numeric"),
    key = "id",
    rules = list(positive = ~ amount > 0)
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, columns = c(extra = "numeric"))
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", grain = "One month")
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(
      old,
      version = "2",
      grain = "One month",
      key = character()
    )
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", remove = "amount")
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", remove = "amount", required = "id")
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", columns = c(id = "character"))
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", columns = c(amount = "integer"))
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", remove = "missing")
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(old, version = "2", typo = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    dr_contract_update(
      old,
      version = "2",
      remove = "amount",
      columns = c(amount = "numeric")
    )
  )
})
