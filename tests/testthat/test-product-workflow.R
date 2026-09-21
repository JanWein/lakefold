test_that("workflow slots can be reused, updated, removed and bound at execution", {
  spec <- product("orders") |> add_quality(~ amount >= 0)
  preparation <- recipe() |> step_mutate(amount = amount * 2)
  flow <- workflow() |> add_product(spec) |> add_recipe(preparation)
  original <- flow
  expect_identical(extract_product(flow), spec)
  expect_identical(extract_recipe(flow), preparation)
  first <- trial(flow, data = data.frame(amount = 10))
  second <- trial(flow, data = data.frame(amount = 30))
  expect_equal(collect(first)$amount, 20)
  expect_equal(collect(second)$amount, 60)
  changed <- update_recipe(flow, recipe() |> step_mutate(amount = amount + 1))
  expect_equal(
    collect(trial(changed, data = data.frame(amount = 10)))$amount,
    11
  )
  expect_equal(
    collect(trial(remove_recipe(flow), data = data.frame(amount = 10)))$amount,
    10
  )
  renamed <- update_product(flow, product("new_orders"))
  expect_equal(run(renamed, data = data.frame(amount = 10))$asset, "new_orders")
  expect_null(remove_product(flow)$product)
  expect_identical(flow, original)
})

test_that("preflight and printing never read sources", {
  calls <- 0L
  flow <- workflow() |>
    add_recipe(recipe() |> step_mutate(amount = amount * 2)) |>
    add_source(function() {
      calls <<- calls + 1L
      data.frame(amount = 10)
    }) |>
    add_product(product("orders"))
  expect_identical(validate(flow), flow)
  expect_identical(attr(plan(flow), "complete"), TRUE)
  expect_output(print(flow), "orders")
  expect_equal(inspect(flow)$type, "product workflow")
  expect_identical(calls, 0L)
  expect_equal(collect(run(flow))$amount, 20)
  expect_identical(calls, 1L)
})

test_that("failed gates and trials never invoke the configured writer", {
  writes <- 0L
  local_adapter_method(
    "check_component",
    "workflow_test_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "write_target",
    "workflow_test_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list(type = "test", rows = nrow(data))
    }
  )
  flow <- workflow() |>
    add_product(product("orders") |> add_quality(~ amount > 0)) |>
    add_recipe(recipe() |> step_mutate(amount = amount * 2)) |>
    set_target(structure(list(), class = "workflow_test_target"))
  good <- data.frame(amount = 10)
  bad <- data.frame(amount = -10)
  expect_equal(trial(flow, data = good)$status, "completed")
  expect_identical(writes, 0L)
  expect_equal(
    publish(flow, data = bad, stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_identical(writes, 0L)
  expect_equal(collect(publish(flow, data = good))$amount, 20)
  expect_identical(writes, 1L)
})

test_that("bound deliveries can change without mutating sources or recipe", {
  flow <- workflow() |>
    add_product(product("orders")) |>
    add_recipe(recipe() |> step_mutate(amount = amount * 2)) |>
    add_source(data.frame(amount = 10), name = "delivery")
  expect_equal(collect(trial(flow, data = data.frame(amount = 20)))$amount, 40)
  expect_equal(
    collect(trial(
      flow,
      sources = list(delivery = data.frame(amount = 30))
    ))$amount,
    60
  )
  expect_equal(collect(trial(flow))$amount, 20)
})

test_that("workflow execution defaults and explicit rule engines remain separate", {
  flow <- workflow(execution = execution_config(quality = "pointblank")) |>
    add_product(
      product("orders") |>
        add_quality(
          quality_rule("positive", ~ amount > 0) |> set_engine("native")
        )
    )
  expect_equal(trial(flow, data = data.frame(amount = 10))$status, "completed")
})

test_that("invalid or conflicting slots explain how to repair them", {
  expect_snapshot(error = TRUE, add_product(workflow(), 1))
})
test_that("adding an occupied product slot requires update", {
  expect_snapshot(
    error = TRUE,
    workflow() |> add_product(product("a")) |> add_product(product("b"))
  )
})
test_that("adding an occupied recipe slot requires update", {
  expect_snapshot(
    error = TRUE,
    workflow() |> add_recipe(recipe()) |> add_recipe(recipe())
  )
})
test_that("preparation stays in a dedicated workflow slot", {
  expect_snapshot(
    error = TRUE,
    workflow() |> add_product(product("a") |> dplyr::mutate(amount = 1))
  )
})
test_that("sources cannot silently shadow product inputs", {
  expect_snapshot(
    error = TRUE,
    workflow() |>
      add_source(data.frame(id = 1L)) |>
      add_product(product("a", data.frame(id = 2L)))
  )
})
test_that("incomplete workflows explain the missing product", {
  expect_snapshot(error = TRUE, trial(workflow(), data = data.frame(id = 1L)))
})

test_that("model products use the same assembly without flattening", {
  skip_if_not_installed("dm")
  model <- dm::dm(
    customers = data.frame(id = 1:2),
    policies = data.frame(policy_id = 1:2, customer_id = 1:2)
  ) |>
    dm::dm_add_pk(customers, id) |>
    dm::dm_add_pk(policies, policy_id) |>
    dm::dm_add_fk(policies, customer_id, customers)
  flow <- workflow() |> add_product(product("portfolio", model))
  result <- trial(flow)
  expect_s3_class(collect(result), "dm")
  expect_equal(nrow(collect(result)$policies), 2L)
})

test_that("nested modular workflows share dependencies and trials disable their writers", {
  reads <- 0L
  writes <- 0L
  local_adapter_method(
    "check_component",
    "nested_workflow_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "write_target",
    "nested_workflow_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list(type = "test")
    }
  )
  upstream <- workflow() |>
    add_product(product("upstream")) |>
    add_recipe(recipe() |> step_mutate(amount = amount * 2)) |>
    add_source(function() {
      reads <<- reads + 1L
      data.frame(id = 1:2, amount = c(10, 20))
    }) |>
    set_target(structure(list(), class = "nested_workflow_target"))
  downstream <- workflow() |>
    add_product(product("downstream")) |>
    add_source(upstream) |>
    add_recipe(recipe() |> step_lookup(upstream, by = "id", name = "same"))
  result <- trial(downstream)
  expect_equal(collect(result)$amount.x, c(20, 40))
  expect_identical(reads, 1L)
  expect_identical(writes, 0L)
})

test_that("lake workflow publications retain checked immutable releases", {
  skip_if_not_installed("duckdb")
  destination <- withr::local_tempdir()
  flow <- workflow() |>
    add_product(product("orders") |> add_quality(~ amount >= 0)) |>
    add_recipe(recipe() |> step_mutate(amount = amount * 2))
  first <- publish(flow, to = destination, data = data.frame(amount = 10))
  second <- publish(flow, to = destination, data = data.frame(amount = 20))
  expect_equal(collect(first)$amount, 20)
  expect_equal(collect(second)$amount, 40)
  expect_equal(
    publish(
      flow,
      to = destination,
      data = data.frame(amount = -1),
      stop_on_failure = FALSE
    )$status,
    "blocked"
  )
  expect_equal(collect(second)$amount, 40)
})
