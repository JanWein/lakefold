test_that("execution defaults are explicit values and definitions stay unchanged", {
  reads <- 0L
  definition <- tw_product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1:2)
  }) |>
    tw_add_quality(~ id > 0)
  original <- definition
  execution <- tw_execution_config()
  expect_equal(reads, 0L)
  result <- tw_run(definition, execution = execution)
  expect_equal(tw_collect(result)$id, 1:2)
  expect_equal(reads, 1L)
  expect_identical(definition, original)
  expect_identical(execution, tw_execution_config())
})

test_that("formula engines propagate through contracts and lookup dependencies", {
  skip_if_not_installed("pointblank")
  skip_if_not_installed("dm")
  reference <- tw_product(
    "customers",
    data.frame(id = 1:2, region = c("a", "b"))
  ) |>
    tw_add_quality(~ id > 0, name = "customer_positive")
  definition <- tw_product("orders", data.frame(id = 1:2)) |>
    tw_add_contract(tw_contract(
      "orders_schema",
      columns = c(id = "integer", region = "character"),
      rules = list(tw_quality_rule("contract_positive", ~ id > 0))
    )) |>
    tw_add_quality(~ id > 0, name = "inherited") |>
    tw_add_quality(~ id > 0, name = "explicit", engine = "native") |>
    tw_add_quality(function(data) data$id > 0, name = "function") |>
    tw_add_lookup(reference, by = "id")
  execution <- tw_execution_config(quality = "pointblank", relationships = "dm")
  result <- tw_run(definition, execution = execution)
  rules <- tw_quality(result)
  expect_equal(
    rules$engine[match(
      c("contract_positive", "inherited", "explicit", "function"),
      rules$rule
    )],
    c("pointblank", "pointblank", "r", "r")
  )
  expect_equal(tw_collect(result)$region, c("a", "b"))
  resolved <- apply_execution_defaults(definition, execution)
  expect_identical(resolved$transforms[[1]]$engine, "dm")
  expect_identical(
    resolved$transforms[[1]]$source$quality[[1]]$engine,
    "pointblank"
  )
  explicit <- definition |>
    tw_add_lookup(data.frame(id = 1:2), by = "id", engine = "native")
  expect_identical(
    apply_execution_defaults(explicit, execution)$transforms[[2]]$engine,
    "native"
  )
})

test_that("defaults preserve configured dependency targets and layers", {
  root <- withr::local_tempdir()
  dependency <- tw_product("customers", data.frame(id = 1L)) |>
    tw_set_target(tw_target_lake(
      file.path(root, "existing"),
      layer = "validated"
    ))
  definition <- tw_product("orders", dependency)
  execution <- tw_execution_config(
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
  local_mocked_bindings(tw_write_target.NULL = function(...) {
    writes <<- writes + 1L
    list(type = "memory")
  })
  result <- tw_product("orders", data.frame(id = -1L)) |>
    tw_add_quality(~ id > 0) |>
    tw_run(
      execution = tw_execution_config(quality = "pointblank"),
      stop_on_failure = FALSE
    )
  expect_identical(result$status, "blocked")
  expect_equal(writes, 0L)
})

test_that("cycles are rejected before source acquisition", {
  reads <- 0L
  child <- tw_product("orders", function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  })
  parent <- tw_product("orders", child)
  condition <- tryCatch(
    tw_run(parent, execution = tw_execution_config()),
    error = identity
  )
  expect_s3_class(condition, "tw_dependency_cycle")
  expect_equal(reads, 0L)
})

test_that("invalid defaults are rejected clearly", {
  expect_snapshot(error = TRUE, tw_execution_config(quality = "unknown"))
})

test_that("incompatible layers are rejected before source acquisition", {
  reads <- 0L
  source <- function() {
    reads <<- reads + 1L
    data.frame(id = 1L)
  }
  condition <- tryCatch(
    tw_run(
      tw_product("orders", source),
      execution = tw_execution_config(layer = "staging")
    ),
    error = identity
  )
  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "requires a lake target")
  condition <- tryCatch(
    tw_ingest(source, execution = tw_execution_config(layer = "staging")),
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
  local_mocked_bindings(tw_run = function(pipeline, execution, ...) {
    captured <<- apply_execution_defaults(pipeline, execution)
    captured
  })
  root <- normalizePath(withr::local_tempdir(), winslash = "/", mustWork = TRUE)
  definition <- tw_product("orders", data.frame(id = 1L))
  execution <- tw_execution_config(
    to = file.path(root, "defaults"),
    layer = "staging"
  )
  tw_publish(
    definition,
    to = file.path(root, "explicit"),
    layer = "validated",
    execution = execution
  )
  expect_identical(captured$target$destination, file.path(root, "explicit"))
  expect_identical(captured$target$layer, "validated")
  tw_publish(definition, execution = execution)
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
  defaults <- tw_execution_config(
    quality = "pointblank",
    to = file.path(root, "default")
  )
  tw_ingest(data.frame(id = 1L), quality = ~ id > 0, execution = defaults)
  expect_identical(seen$to, tw_lake_config(path = file.path(root, "default")))
  expect_identical(seen$definition$quality[[1]]$engine, "pointblank")
  tw_ingest(
    data.frame(id = 1L),
    to = file.path(root, "explicit"),
    execution = defaults
  )
  expect_identical(seen$to, tw_lake_config(path = file.path(root, "explicit")))
  expect_identical(dir.exists(file.path(root, "default")), FALSE)
})

test_that("dbt rejects product execution defaults before invoking its runner", {
  project <- structure(list(), class = "tw_dbt_project")
  result <- structure(list(), class = "tw_dbt_result")
  condition <- tryCatch(
    tw_run(project, execution = tw_execution_config()),
    error = identity
  )
  expect_match(conditionMessage(condition), "Configure dbt through its project")
  condition <- tryCatch(
    tw_publish(result, execution = tw_execution_config()),
    error = identity
  )
  expect_match(conditionMessage(condition), "Configure dbt through its project")
})


test_that("execution destinations do not publish intermediate dependencies", {
  root <- withr::local_tempdir()
  child <- tw_product("customers", data.frame(id = 1L))
  definition <- tw_product("orders", child)
  resolved <- apply_execution_defaults(
    definition,
    tw_execution_config(to = root, layer = "staging")
  )
  expect_null(resolved$sources[[1]]$target)
  expect_identical(resolved$target$layer, "staging")
})

test_that("engine defaults preserve declared contracts and immutable releases", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("pointblank")
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  declaration <- tw_contract(
    "orders_schema",
    columns = c(id = "integer"),
    rules = list(tw_quality_rule("positive", ~ id > 0))
  )
  definition <- tw_product(
    "orders",
    data.frame(id = 1:2),
    code_version = "v1"
  ) |>
    tw_add_contract(declaration)
  first <- tw_publish(definition, to = lake, cache = TRUE)
  assets <- tw_registry(lake, "assets")
  declared <- assets[assets$id == declaration$id, ]
  alternate <- tw_execution_config(quality = "pointblank")
  resolved <- apply_execution_defaults(definition, alternate)
  expect_identical(resolved$contract, declaration)
  second <- tw_publish(
    definition,
    to = lake,
    execution = alternate,
    cache = TRUE
  )
  expect_identical(second$status, "published")
  expect_identical(
    tw_quality(first)$engine[tw_quality(first)$rule == "positive"],
    "r"
  )
  expect_identical(
    tw_quality(second)$engine[tw_quality(second)$rule == "positive"],
    "pointblank"
  )
  expect_identical(tw_collect(first), tw_collect(second))
  assets <- tw_registry(lake, "assets")
  expect_identical(assets[assets$id == declaration$id, ], declared)
  expect_identical(nrow(tw_registry(lake, "releases")), 2L)
  cached <- tw_publish(
    definition,
    to = lake,
    execution = alternate,
    cache = TRUE
  )
  expect_identical(cached$status, "cached")
  expect_identical(cached$release_id, second$release_id)
  changed <- declaration
  changed$rules <- list(tw_quality_rule("positive", ~ id > 1))
  condition <- tryCatch(
    tw_publish(
      tw_add_contract(definition, changed),
      to = lake,
      execution = alternate
    ),
    error = identity
  )
  expect_match(
    conditionMessage(condition),
    "Definition changed without a version bump"
  )
  expect_identical(tw_collect(first)$id, 1:2)
  expect_identical(tw_read_release(lake, "orders")$id, 1:2)
})

test_that("ingestion registers the declared contract before resolved checks", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("pointblank")
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  declaration <- tw_contract(
    "delivery_schema",
    columns = c(id = "integer"),
    rules = list(tw_quality_rule("positive", ~ id > 0))
  )
  definition <- tw_product("delivery", data.frame(id = 1L)) |>
    tw_add_contract(declaration)
  first <- tw_ingest(definition, lake)
  second <- tw_ingest(
    definition,
    lake,
    execution = tw_execution_config(quality = "pointblank")
  )
  expect_identical(second$status, "published")
  assets <- tw_registry(lake, "assets")
  expect_identical(
    assets$fingerprint[assets$id == declaration$id],
    fingerprint(declaration)
  )
  expect_identical(
    tw_quality(second)$engine[tw_quality(second)$rule == "positive"],
    "pointblank"
  )
  expect_identical(tw_collect(first)$id, 1L)
})

test_that("explicit product versions still protect execution definitions", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("pointblank")
  lake <- tw_open_lake(withr::local_tempdir())
  withr::defer(tw_close_lake(lake))
  definition <- tw_product(
    "orders",
    data.frame(id = 1L),
    version = "1",
    code_version = "v1"
  ) |>
    tw_add_contract(tw_contract(
      "orders_schema",
      columns = c(id = "integer"),
      rules = list(tw_quality_rule("positive", ~ id > 0))
    ))
  first <- tw_publish(definition, to = lake, cache = TRUE)
  condition <- tryCatch(
    tw_publish(
      definition,
      to = lake,
      cache = TRUE,
      execution = tw_execution_config(quality = "pointblank")
    ),
    error = identity
  )
  expect_match(
    conditionMessage(condition),
    "Definition changed without a version bump: orders 1"
  )
  expect_identical(tw_collect(first)$id, 1L)
  expect_identical(nrow(tw_registry(lake, "releases")), 1L)
})
