test_that("workflow slots can be reused, updated, removed and bound at execution", {
  spec <- tw_product("orders") |> tw_add_quality(~ amount >= 0)
  preparation <- tw_recipe() |> tw_step_mutate(amount = amount * 2)
  flow <- tw_workflow() |> tw_add_product(spec) |> tw_add_recipe(preparation)
  original <- flow
  expect_identical(tw_extract_product(flow), spec)
  expect_identical(tw_extract_recipe(flow), preparation)
  first <- tw_trial(flow, data = data.frame(amount = 10))
  second <- tw_trial(flow, data = data.frame(amount = 30))
  expect_equal(tw_collect(first)$amount, 20)
  expect_equal(tw_collect(second)$amount, 60)
  changed <- tw_update_recipe(
    flow,
    tw_recipe() |> tw_step_mutate(amount = amount + 1)
  )
  expect_equal(
    tw_collect(tw_trial(changed, data = data.frame(amount = 10)))$amount,
    11
  )
  expect_equal(
    tw_collect(tw_trial(
      tw_remove_recipe(flow),
      data = data.frame(amount = 10)
    ))$amount,
    10
  )
  renamed <- tw_update_product(flow, tw_product("new_orders"))
  expect_equal(
    tw_run(renamed, data = data.frame(amount = 10))$asset,
    "new_orders"
  )
  expect_null(tw_remove_product(flow)$product)
  expect_identical(flow, original)
})

test_that("preflight and printing never read sources", {
  calls <- 0L
  flow <- tw_workflow() |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2)) |>
    tw_add_source(function() {
      calls <<- calls + 1L
      data.frame(amount = 10)
    }) |>
    tw_add_product(tw_product("orders"))
  expect_identical(tw_validate(flow), flow)
  expect_identical(attr(tw_plan(flow), "complete"), TRUE)
  expect_output(print(flow), "orders")
  expect_equal(tw_inspect(flow)$type, "product workflow")
  expect_identical(calls, 0L)
  expect_equal(tw_collect(tw_run(flow))$amount, 20)
  expect_identical(calls, 1L)
})

test_that("failed gates and trials never invoke the configured writer", {
  writes <- 0L
  local_adapter_method(
    "tw_check_component",
    "workflow_test_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "tw_write_target",
    "workflow_test_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list(type = "test", rows = nrow(data))
    }
  )
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders") |> tw_add_quality(~ amount > 0)) |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2)) |>
    tw_set_target(structure(list(), class = "workflow_test_target"))
  good <- data.frame(amount = 10)
  bad <- data.frame(amount = -10)
  expect_equal(tw_trial(flow, data = good)$status, "completed")
  expect_identical(writes, 0L)
  expect_equal(
    tw_publish(flow, data = bad, stop_on_failure = FALSE)$status,
    "blocked"
  )
  expect_identical(writes, 0L)
  expect_equal(tw_collect(tw_publish(flow, data = good))$amount, 20)
  expect_identical(writes, 1L)
})

test_that("bound deliveries can change without mutating sources or recipe", {
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders")) |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2)) |>
    tw_add_source(data.frame(amount = 10), name = "delivery")
  expect_equal(
    tw_collect(tw_trial(flow, data = data.frame(amount = 20)))$amount,
    40
  )
  expect_equal(
    tw_collect(tw_trial(
      flow,
      sources = list(delivery = data.frame(amount = 30))
    ))$amount,
    60
  )
  expect_equal(tw_collect(tw_trial(flow))$amount, 20)
})

test_that("workflow execution defaults and explicit rule engines remain separate", {
  flow <- tw_workflow(
    execution = tw_execution_config(quality = "pointblank")
  ) |>
    tw_add_product(
      tw_product("orders") |>
        tw_add_quality(
          tw_quality_rule("positive", ~ amount > 0) |> tw_set_engine("native")
        )
    )
  expect_equal(
    tw_trial(flow, data = data.frame(amount = 10))$status,
    "completed"
  )
})

test_that("invalid or conflicting slots explain how to repair them", {
  expect_snapshot(error = TRUE, tw_add_product(tw_workflow(), 1))
})
test_that("adding an occupied product slot requires update", {
  expect_snapshot(
    error = TRUE,
    tw_workflow() |>
      tw_add_product(tw_product("a")) |>
      tw_add_product(tw_product("b"))
  )
})
test_that("adding an occupied recipe slot requires update", {
  expect_snapshot(
    error = TRUE,
    tw_workflow() |> tw_add_recipe(tw_recipe()) |> tw_add_recipe(tw_recipe())
  )
})
test_that("preparation stays in a dedicated workflow slot", {
  expect_snapshot(
    error = TRUE,
    tw_workflow() |>
      tw_add_product(tw_product("a") |> dplyr::mutate(amount = 1))
  )
})
test_that("sources cannot silently shadow product inputs", {
  expect_snapshot(
    error = TRUE,
    tw_workflow() |>
      tw_add_source(data.frame(id = 1L)) |>
      tw_add_product(tw_product("a", data.frame(id = 2L)))
  )
})
test_that("incomplete workflows explain the missing product", {
  expect_snapshot(
    error = TRUE,
    tw_trial(tw_workflow(), data = data.frame(id = 1L))
  )
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
  flow <- tw_workflow() |> tw_add_product(tw_product("portfolio", model))
  result <- tw_trial(flow)
  expect_s3_class(tw_collect(result), "dm")
  expect_equal(nrow(tw_collect(result)$policies), 2L)
})

test_that("nested modular workflows share dependencies and trials disable their writers", {
  reads <- 0L
  writes <- 0L
  local_adapter_method(
    "tw_check_component",
    "nested_workflow_target",
    function(x, ...) invisible(x)
  )
  local_adapter_method(
    "tw_write_target",
    "nested_workflow_target",
    function(target, data, context, ...) {
      writes <<- writes + 1L
      list(type = "test")
    }
  )
  upstream <- tw_workflow() |>
    tw_add_product(tw_product("upstream")) |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2)) |>
    tw_add_source(function() {
      reads <<- reads + 1L
      data.frame(id = 1:2, amount = c(10, 20))
    }) |>
    tw_set_target(structure(list(), class = "nested_workflow_target"))
  downstream <- tw_workflow() |>
    tw_add_product(tw_product("downstream")) |>
    tw_add_source(upstream) |>
    tw_add_recipe(
      tw_recipe() |> tw_step_lookup(upstream, by = "id", name = "same")
    )
  result <- tw_trial(downstream)
  expect_equal(tw_collect(result)$amount.x, c(20, 40))
  expect_identical(reads, 1L)
  expect_identical(writes, 0L)
})

test_that("lake workflow publications retain checked immutable releases", {
  skip_if_not_installed("duckdb")
  destination <- withr::local_tempdir()
  flow <- tw_workflow() |>
    tw_add_product(tw_product("orders") |> tw_add_quality(~ amount >= 0)) |>
    tw_add_recipe(tw_recipe() |> tw_step_mutate(amount = amount * 2))
  first <- tw_publish(flow, to = destination, data = data.frame(amount = 10))
  second <- tw_publish(flow, to = destination, data = data.frame(amount = 20))
  expect_equal(tw_collect(first)$amount, 20)
  expect_equal(tw_collect(second)$amount, 40)
  expect_equal(
    tw_publish(
      flow,
      to = destination,
      data = data.frame(amount = -1),
      stop_on_failure = FALSE
    )$status,
    "blocked"
  )
  expect_equal(tw_collect(second)$amount, 40)
})
