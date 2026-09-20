# Generated from vignettes/getting-started.Rmd.
if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Install optional duckdb to run this example.")
}
local({
  on.exit(
    if (exists("lake", inherits = FALSE) && DBI::dbIsValid(lake$con)) {
      close_lake(lake)
    },
    add = TRUE
  )
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

  reserves <- product("reserves", august) |>
    add_contract(contract(
      columns = c(entity = "character", date = "Date", amount = "numeric"),
      key = c("entity", "date")
    )) |>
    add_quality(~ amount >= 0, name = "nonnegative") |>
    set_target(target_lake(root, partition_by = "date"))

  first <- run(reserves, business_date = "2026-08-31")
  sum(collect(first)$amount)
  stopifnot(first$status == "published", sum(collect(first)$amount) == 350)

  total_reserve <- metric(
    "total_reserve",
    "reserves",
    expr = sum(amount, na.rm = TRUE),
    time_column = "date",
    time_behavior = "stock",
    unit = "EUR",
    approved = TRUE,
    code_version = "report-v1"
  )
  as_reported <- measure(first, total_reserve, at = august_date)
  lake <- open_lake(root)
  report_release(
    lake,
    "august-report-v1",
    results = list(total_reserve = as_reported),
    code_version = "report-v1"
  )
  close_lake(lake)
  stopifnot(as_reported$value == 350)

  corrected <- august
  corrected$amount[corrected$entity == "South"] <- 270
  reserves <- reserves |>
    add_source(corrected, replace = TRUE)
  correction <- run(reserves, business_date = "2026-08-31")
  sum(collect(correction)$amount)
  sum(collect(first)$amount)
  stopifnot(
    sum(collect(correction)$amount) == 370,
    sum(collect(first)$amount) == 350
  )

  bad <- rbind(corrected, corrected[2, ])
  blocked <- reserves |>
    add_source(bad, replace = TRUE) |>
    run(stop_on_failure = FALSE)
  incidents(blocked)
  stopifnot(blocked$status == "blocked")

  september <- data.frame(
    entity = c("North", "South"),
    date = rep(as.Date("2026-09-30"), 2),
    amount = c(110, 280)
  )
  latest <- reserves |>
    add_source(september, replace = TRUE) |>
    run(business_date = "2026-09-30")
  collect(latest) |> dplyr::arrange(date, entity)
  stopifnot(nrow(collect(latest)) == 4L)

  monthly_totals <- product("monthly_totals", latest) |>
    dplyr::group_by(date) |>
    dplyr::summarise(total = sum(amount, na.rm = TRUE), .groups = "drop")
  totals <- collect(run(monthly_totals)) |> dplyr::arrange(date)
  totals
  stopifnot(identical(totals$total, c(370, 390)))

  lake <- open_lake(root, read_only = TRUE)
  issued <- report_read(lake, "august-report-v1", values_only = TRUE)
  current <- measure(lake, total_reserve, at = august_date)
  issued$total_reserve$value
  current$value
  stopifnot(issued$total_reserve$value == 350, current$value == 370)
  close_lake(lake)

  unlink(root, recursive = TRUE)
})
