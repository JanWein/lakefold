test_that("execution defaults are explicit values and definitions stay unchanged", {
  reads <- 0L
  definition <- product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1:2)
  }) |>
    add_quality(~ id > 0)
  original <- definition
  execution <- execution_config()
  expect_equal(reads, 0L)
  result <- run(definition, execution = execution)
  expect_equal(collect(result)$id, 1:2)
  expect_equal(reads, 1L)
  expect_identical(definition, original)
  expect_identical(execution, execution_config())
})

test_that("formula engines propagate through contracts and lookup dependencies", {
  skip_if_not_installed("pointblank")
  skip_if_not_installed("dm")
  reference <- product(
    "customers",
    data.frame(id = 1:2, region = c("a", "b"))
  ) |>
    add_quality(~ id > 0, name = "customer_positive")
  definition <- product("orders", data.frame(id = 1:2)) |>
    add_contract(contract(
      "orders_schema",
      columns = c(id = "integer", region = "character"),
      rules = list(quality_rule("contract_positive", ~ id > 0))
    )) |>
    add_quality(~ id > 0, name = "inherited") |>
    add_quality(~ id > 0, name = "explicit", engine = "native") |>
    add_quality(function(data) data$id > 0, name = "function") |>
    add_lookup(reference, by = "id")
  execution <- execution_config(quality = "pointblank", relationships = "dm")
  result <- run(definition, execution = execution)
  rules <- quality(result)
  expect_equal(
    rules$engine[match(
      c("contract_positive", "inherited", "explicit", "function"),
      rules$rule
    )],
    c("pointblank", "pointblank", "r", "r")
  )
  expect_equal(collect(result)$region, c("a", "b"))
  resolved <- apply_execution_defaults(definition, execution)
  expect_identical(resolved$transforms[[1]]$engine, "dm")
  expect_identical(
    resolved$transforms[[1]]$source$quality[[1]]$engine,
    "pointblank"
  )
  explicit <- definition |>
    add_lookup(data.frame(id = 1:2), by = "id", engine = "native")
  expect_identical(
    apply_execution_defaults(explicit, execution)$transforms[[2]]$engine,
    "native"
  )
})

test_that("defaults preserve configured dependency targets and layers", {
  root <- withr::local_tempdir()
  dependency <- product("customers", data.frame(id = 1L)) |>
    set_target(target_lake(file.path(root, "existing"), layer = "validated"))
  definition <- product("orders", dependency)
  execution <- execution_config(
    to = file.path(root, "default"),
    layer = "staging"
  )
  resolved <- apply_execution_defaults(definition, execution)
  expect_identical(resolved$sources[[1]]$target, dependency$target)
  expect_identical(resolved$target$layer, "staging")
  expect_identical(dir.exists(file.path(root, "default")), FALSE)
})

test_that("publication gates still prevent writes with alternate defaults", {
  skip_if_not_installed("pointblank")
  writes <- 0L
  local_mocked_bindings(write_target.NULL = function(...) {
    writes <<- writes + 1L
    list(type = "memory")
  })
  result <- product("orders", data.frame(id = -1L)) |>
    add_quality(~ id > 0) |>
    run(
      execution = execution_config(quality = "pointblank"),
      stop_on_failure = FALSE
    )
  expect_identical(result$status, "blocked")
  expect_equal(writes, 0L)
})

test_that("cycles are rejected before source acquisition", {
  reads <- 0L
  child <- product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  })
  parent <- product("orders", child)
  condition <- tryCatch(
    run(parent, execution = execution_config()),
    error = identity
  )
  expect_s3_class(condition, "tw_dependency_cycle")
  expect_equal(reads, 0L)
})

test_that("invalid defaults are rejected clearly", {
  expect_snapshot(error = TRUE, execution_config(quality = "unknown"))
})

test_that("incompatible layers are rejected before source acquisition", {
  reads <- 0L
  source <- function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  }
  condition <- tryCatch(
    run(
      product("orders", source),
      execution = execution_config(layer = "staging")
    ),
    error = identity
  )
  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "requires a lake target")
  condition <- tryCatch(
    ingest(source, execution = execution_config(layer = "staging")),
    error = identity
  )
  expect_s3_class(condition, "error")
  expect_match(
    conditionMessage(condition),
    "Ingestion requires execution layer"
  )
  expect_equal(reads, 0L)
})

test_that("explicit publication destination and layer override root defaults", {
  captured <- NULL
  local_mocked_bindings(run = function(pipeline, execution, ...) {
    captured <<- apply_execution_defaults(pipeline, execution)
    captured
  })
  root <- withr::local_tempdir()
  definition <- product("orders", data.frame(id = 1L))
  execution <- execution_config(
    to = file.path(root, "defaults"),
    layer = "staging"
  )
  publish(
    definition,
    to = file.path(root, "explicit"),
    layer = "validated",
    execution = execution
  )
  expect_identical(captured$target$destination, file.path(root, "explicit"))
  expect_identical(captured$target$layer, "validated")
  publish(definition, execution = execution)
  expect_identical(captured$target$destination, file.path(root, "defaults"))
  expect_identical(captured$target$layer, "staging")
})

test_that("ingestion resolves default destinations and engines before connecting", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("pointblank")
  root <- withr::local_tempdir()
  seen <- NULL
  local_mocked_bindings(with_execution_lake = function(to, fun) {
    seen <<- list(to = to, definition = environment(fun)$definition)
    invisible(NULL)
  })
  defaults <- execution_config(
    quality = "pointblank",
    to = file.path(root, "default")
  )
  ingest(data.frame(id = 1L), quality = ~ id > 0, execution = defaults)
  expect_identical(seen$to, lake_config(path = file.path(root, "default")))
  expect_identical(seen$definition$quality[[1]]$engine, "pointblank")
  ingest(
    data.frame(id = 1L),
    to = file.path(root, "explicit"),
    execution = defaults
  )
  expect_identical(seen$to, lake_config(path = file.path(root, "explicit")))
  expect_identical(dir.exists(file.path(root, "default")), FALSE)
})

test_that("dbt rejects product execution defaults before invoking its runner", {
  project <- structure(list(), class = "tw_dbt_project")
  result <- structure(list(), class = "tw_dbt_result")
  condition <- tryCatch(
    run(project, execution = execution_config()),
    error = identity
  )
  expect_match(conditionMessage(condition), "Configure dbt through its project")
  condition <- tryCatch(
    publish(result, execution = execution_config()),
    error = identity
  )
  expect_match(conditionMessage(condition), "Configure dbt through its project")
})


test_that("execution destinations do not publish intermediate dependencies", {
  root <- withr::local_tempdir()
  child <- product("customers", data.frame(id = 1L))
  definition <- product("orders", child)
  resolved <- apply_execution_defaults(
    definition,
    execution_config(to = root, layer = "staging")
  )
  expect_null(resolved$sources[[1]]$target)
  expect_identical(resolved$target$layer, "staging")
})
