test_that("native thresholds are evaluated independently for each pointblank segment", {
  skip_if_not_installed("pointblank")
  data <- data.frame(
    entity = rep(c("A", "B"), each = 100),
    amount = rep(1, 200)
  )
  data$amount[1:3] <- -1
  contract <- dl_contract(
    "amounts",
    "1",
    "Analytics",
    "Amounts",
    "One amount",
    c(entity = "character", amount = "numeric"),
    rules = list(
      dl_pointblank(
        "positive",
        function(data) {
          pointblank::create_agent(
            data,
            actions = pointblank::action_levels(warn_at = 0.005, stop_at = 0.05)
          ) |>
            pointblank::col_vals_gte(
              "amount",
              0,
              segments = pointblank::vars(entity)
            )
        },
        policy = "agent"
      )
    )
  )
  quality <- dl_validate(data, contract, keep_agents = TRUE)
  checks <- quality[quality$engine == "pointblank", ]
  expect_equal(checks$status, c("warning", "passed"))
  expect_equal(checks$n_total, c(100, 100))
  expect_equal(length(unique(checks$segment)), 2L)
  expect_equal(grepl('"A"', checks$segment[[1]], fixed = TRUE), TRUE)
  expect_equal(lakefold:::quality_ok(quality), TRUE)
  data$amount[4:5] <- -1
  checks <- dl_validate(data, contract)
  expect_equal(
    checks$status[checks$engine == "pointblank"],
    c("failed", "passed")
  )
  expect_equal(lakefold:::quality_ok(checks), FALSE)
  expect_equal(is.null(attr(checks, "pointblank_agents")), TRUE)
})

test_that("native policy fails closed for inactive, errored and unconfigured checks", {
  skip_if_not_installed("pointblank")
  builders <- list(
    function(data) {
      pointblank::create_agent(data) |> pointblank::col_vals_gte("x", 0)
    },
    function(data) {
      pointblank::create_agent(
        data,
        actions = pointblank::action_levels(warn_at = 1)
      ) |>
        pointblank::col_vals_gte("x", 0, active = FALSE)
    },
    function(data) {
      pointblank::create_agent(
        data,
        actions = pointblank::action_levels(stop_at = 1)
      ) |>
        pointblank::col_vals_gte("missing", 0)
    }
  )
  for (build in builders) {
    contract <- dl_contract(
      "x",
      "1",
      "Analytics",
      "Values",
      "One value",
      c(x = "numeric"),
      rules = list(dl_pointblank("check", build, policy = "agent"))
    )
    quality <- dl_validate(data.frame(x = 1), contract)
    expect_equal(lakefold:::quality_ok(quality), FALSE)
    expect_equal(any(quality$status %in% c("error", "not_checked")), TRUE)
  }
})

test_that("legacy rule policy remains independent of native action levels", {
  skip_if_not_installed("pointblank")
  contract <- dl_contract(
    "x",
    "1",
    "Analytics",
    "Values",
    "One value",
    c(x = "numeric"),
    rules = list(dl_pointblank(
      "check",
      function(data) {
        pointblank::create_agent(
          data,
          actions = pointblank::action_levels(stop_at = 1)
        ) |>
          pointblank::col_vals_gte("x", 0)
      },
      severity = "warning"
    ))
  )
  quality <- dl_validate(data.frame(x = c(-1, 1)), contract)
  expect_equal(quality$status[quality$engine == "pointblank"], "warning")
  expect_equal(lakefold:::quality_ok(quality), TRUE)
})
