# Monthly reporting with lakefold: a complete local example.
# See vignette("getting-started", package = "lakefold") for the explanation.
# Uses synthetic data, checks the results and removes only its own temporary lake.
# Keep these core steps aligned with vignettes/getting-started.Rmd.
(function() {
  library(lakefold)

  root <- tempfile("lakefold-walkthrough-")

  lake <- dl_open(root)
  on.exit(
    {
      dl_close(lake)
      unlink(root, recursive = TRUE)
    },
    add = TRUE
  )

  august_date <- as.Date("2026-08-31")

  august <- data.frame(
    entity = c("North", "South"),
    date = rep(august_date, 2),
    amount = c(100, 250)
  )

  first <- dl_write(lake, august, "reserves")

  print(first$status)

  print(dl_read(lake, "reserves"))

  print(sum(dl_read(lake, "reserves")$amount))

  corrected <- august

  corrected$amount[corrected$entity == "South"] <- 270

  correction <- dl_write(lake, corrected, "reserves")

  print(sum(dl_read(lake, "reserves")$amount))

  print(sum(dl_read(lake, "reserves", release = first$release_id)$amount))

  again <- dl_write(lake, corrected, "reserves")

  print(again$status)

  contract <- dl_contract(
    "reserves.contract",
    columns = c(entity = "character", date = "Date", amount = "numeric"),
    key = c("entity", "date"),
    max_age_hours = NULL
  )

  print(dl_write(lake, corrected, "reserves", contract = contract))

  bad <- rbind(corrected, corrected[2, ])

  blocked <- dl_write(
    lake,
    bad,
    "reserves",
    contract = contract,
    stop_on_failure = FALSE
  )

  print(blocked$status)

  print(dplyr::select(
    dplyr::filter(
      dl_quality(lake, run_id = blocked$run_id),
      status == "failed"
    ),
    rule,
    status,
    n_failed
  ))

  print(sum(dl_read(lake, "reserves")$amount))

  september <- data.frame(
    entity = c("North", "South"),
    date = rep(as.Date("2026-09-30"), 2),
    amount = c(110, 280)
  )

  september_run <- dl_write(
    lake,
    september,
    "reserves",
    contract = contract,
    partition_by = "date",
    business_date = "2026-09-30"
  )

  print(dplyr::arrange(dl_read(lake, "reserves"), date, entity))

  totals_contract <- dl_contract(
    "reserve_totals.contract",
    columns = c(date = "Date", total_reserve = "numeric"),
    key = "date",
    max_age_hours = NULL
  )

  totals <- dl_product(
    "reserve_totals",
    inputs = c(reserves = "reserves"),
    build = function(inputs) {
      dplyr::summarise(
        dplyr::group_by(inputs$reserves, date),
        total_reserve = sum(amount, na.rm = TRUE),
        .groups = "drop"
      )
    },
    contract = totals_contract,
    code_version = "tutorial-v1"
  )

  print(dl_build(lake, totals))

  print(dplyr::arrange(dl_read(lake, "reserve_totals"), date))

  total_reserve <- dl_metric(
    "total_reserve",
    "reserves",
    expr = sum(amount, na.rm = TRUE),
    dimensions = "entity",
    time_column = "date",
    time_behavior = "stock",
    unit = "EUR",
    owner = "Finance",
    description = "Total reserve at one reporting date",
    approved = TRUE,
    code_version = "tutorial-v1"
  )

  current_august <- dl_measure(lake, total_reserve, at = august_date)

  print(current_august)

  print(dl_measure(lake, total_reserve, by = "entity", at = august_date))

  as_reported <- dl_measure(
    lake,
    total_reserve,
    at = august_date,
    release = first$release_id
  )

  report <- dl_report_release(
    lake,
    "august-report-v1",
    results = list(total_reserve = as_reported),
    code_version = "tutorial-v1"
  )

  print(as_reported$value)

  print(current_august$value)

  print(report$id)

  stopifnot(
    first$status == "published",
    correction$status == "published",
    again$status == "cached",
    blocked$status == "blocked",
    any(dl_quality(lake, run_id = blocked$run_id)$rule == "unique_key"),
    nrow(dl_read(lake, "reserves")) == 4L,
    sum(dl_read(lake, "reserves", release = first$release_id)$amount) == 350,
    current_august$value == 370,
    as_reported$value == 350,
    dl_measure(lake, total_reserve, at = as.Date("2026-09-30"))$value == 390,
    identical(
      dplyr::pull(
        dplyr::arrange(dl_read(lake, "reserve_totals"), date),
        total_reserve
      ),
      c(370, 390)
    )
  )

  print(dplyr::select(
    dl_releases(lake, "reserves"),
    release_id,
    business_date,
    quality
  ))

  dl_close(lake)

  lake <- dl_open(root)
  on.exit(
    {
      dl_close(lake)
      unlink(root, recursive = TRUE)
    },
    add = TRUE
  )

  print(sum(dl_read(lake, "reserves", release = first$release_id)$amount))

  dl_close(lake)

  invisible(NULL)
})()
