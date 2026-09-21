# Generated from vignettes/getting-started.Rmd.
if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Install optional duckdb to run this example.")
}
local({
  on.exit(
    if (exists("root", inherits = FALSE)) unlink(root, recursive = TRUE),
    add = TRUE
  )
  library(tidyweave)
  root <- tempfile("monthly-reserves-")
  august_date <- as.Date("2026-08-31")
  august <- data.frame(
    entity = c("North", "South"),
    date = rep(august_date, 2),
    amount = c(100, 250)
  )

  reserves <- tw_product("reserves", august) |>
    tw_add_contract(tw_contract(
      columns = c(entity = "character", date = "Date", amount = "numeric"),
      key = c("entity", "date")
    )) |>
    tw_add_quality(~ amount >= 0, name = "nonnegative") |>
    tw_set_target(tw_target_lake(root, partition_by = "date"))

  first <- tw_publish(reserves, business_date = "2026-08-31")
  sum(tw_collect(first)$amount)
  stopifnot(first$status == "published", sum(tw_collect(first)$amount) == 350)

  metrics <- tw_metric_set(
    "reserves",
    total_reserve = sum(amount, na.rm = TRUE),
    time_column = "date",
    time_behavior = "stock",
    units = "EUR",
    approved = TRUE,
    code_version = "reserves-v1"
  )
  as_reported <- tw_measure(first, metrics = metrics, at = august_date)
  as_reported |>
    tw_report_release("august-report-v1", code_version = "report-v1")
  stopifnot(tw_collect(as_reported)$value == 350)

  corrected <- august
  corrected$amount[corrected$entity == "South"] <- 270
  correction <- tw_publish(
    reserves,
    data = corrected,
    business_date = "2026-08-31"
  )
  sum(tw_collect(correction)$amount)
  sum(tw_collect(first)$amount)
  stopifnot(
    sum(tw_collect(correction)$amount) == 370,
    sum(tw_collect(first)$amount) == 350
  )

  bad <- rbind(corrected, corrected[2, ])
  blocked <- tw_publish(reserves, data = bad, stop_on_failure = FALSE)
  tw_quality_report(blocked)
  stopifnot(blocked$status == "blocked")

  september <- data.frame(
    entity = c("North", "South"),
    date = rep(as.Date("2026-09-30"), 2),
    amount = c(110, 280)
  )
  latest <- tw_publish(reserves, data = september, business_date = "2026-09-30")
  tw_collect(latest) |> dplyr::arrange(date, entity)
  stopifnot(nrow(tw_collect(latest)) == 4L)

  monthly_totals <- tw_product("monthly_totals", latest) |>
    dplyr::group_by(date) |>
    dplyr::summarise(total = sum(amount, na.rm = TRUE), .groups = "drop")
  totals <- tw_collect(tw_trial(monthly_totals)) |> dplyr::arrange(date)
  totals
  stopifnot(identical(totals$total, c(370, 390)))

  issued <- tw_report_read(root, "august-report-v1", values_only = TRUE)
  current <- tw_measure(latest, metrics = metrics, at = august_date)
  issued
  tw_collect(current)
  stopifnot(issued$value == 350, tw_collect(current)$value == 370)

  unlink(root, recursive = TRUE)
})
