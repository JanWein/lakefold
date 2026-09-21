test_that("corrections rerun affected branches and preserve prior results", {
  calls <- c(a = 0L, b = 0L, total = 0L)
  flow <- dr_workflow(
    a = function(payments) {
      calls['a'] <<- calls['a'] + 1L
      sum(payments)
    },
    b = function(policies) {
      calls['b'] <<- calls['b'] + 1L
      sum(policies)
    },
    total = function(a, b) {
      calls['total'] <<- calls['total'] + 1L
      a + b
    },
    inputs = list(payments = 10, policies = 20),
    code_version = "v1"
  )
  first <- dr_run(flow)
  second <- dr_run(flow, inputs = list(payments = 40), previous = first)
  expect_equal(first$results$total, 30)
  expect_equal(second$results$total, 60)
  expect_equal(unname(calls), c(2L, 1L, 2L))
  expect_equal(dr_status(second)$status, c("completed", "reused", "completed"))
  third <- dr_run(flow, previous = second, refresh = "b")
  expect_equal(unname(calls), c(2L, 2L, 3L))
  expect_equal(third$inputs$payments, 40)
})

test_that("failed branches block consumers and retain successful steps for retry", {
  calls <- 0L
  flow <- dr_workflow(
    accepted = function(delivery) {
      dr_trial(dr_product("orders", delivery) |> dr_add_quality(~ amount >= 0))
    },
    independent = function() {
      calls <<- calls + 1L
      2
    },
    total = function(accepted, independent) {
      sum(dr_collect(accepted)$amount) + independent
    },
    inputs = list(delivery = data.frame(amount = -1)),
    code_version = "v1"
  )
  first <- dr_run(flow, stop_on_failure = FALSE)
  expect_equal(dr_status(first)$status, c("failed", "completed", "skipped"))
  second <- dr_run(
    flow,
    previous = first,
    inputs = list(delivery = data.frame(amount = 10))
  )
  expect_equal(second$results$total, 12)
  expect_equal(calls, 1L)
  flow$code_version <- "v2"
  dr_run(flow, previous = second)
  expect_equal(calls, 2L)
})

test_that("invalid dependency graphs fail before any step runs", {
  expect_snapshot(
    error = TRUE,
    dr_workflow(a = function(b) b, b = function(a) a, code_version = "v1")
  )
  expect_snapshot(
    error = TRUE,
    dr_workflow(a = function(unknown) unknown, code_version = "v1")
  )
})
