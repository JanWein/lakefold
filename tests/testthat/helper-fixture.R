fixture <- function(backend = Sys.getenv("TIDYWEAVE_TEST_BACKEND", "duckdb")) {
  root <- tempfile("dataloom-test-")
  dir.create(root)
  lake <- tw_setup_lake(
    tw_registry_duckdb(file.path(root, "meta.duckdb")),
    tw_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"),
    backend = backend
  )
  path <- file.path(root, "input.csv")
  good <- data.frame(
    id = c("a", "b"),
    company = c("Alpha", "Beta"),
    date = as.Date(c("2026-08-31", "2026-08-31")),
    reserve = c(100, 200)
  )
  write <- function(data = good) utils::write.csv(data, path, row.names = FALSE)
  write()
  reader <- function(path) {
    x <- utils::read.csv(
      path,
      colClasses = c("character", "character", "Date", "numeric")
    )
    x
  }
  contract <- tw_contract(
    "risk.contract",
    "1.0.0",
    "Risk",
    "Validated reserves",
    "One contract at a date",
    c(
      id = "character",
      company = "character",
      date = "Date",
      reserve = "numeric"
    ),
    key = c("id", "date"),
    max_age_hours = 48,
    rules = list(tw_quality_rule("nonnegative", function(x) {
      counts <- dplyr::collect(dplyr::summarise(
        x,
        n = dplyr::n(),
        failed = sum(as.integer(reserve < 0), na.rm = TRUE)
      ))
      tw_quality_counts(counts$failed, counts$n)
    }))
  )
  pipeline <- tw_pipeline("risk.import", lake, code_version = "test-code-v1") |>
    tw_step_land(tw_source_file("risk.source", path, reader = reader)) |>
    tw_step_extract() |>
    tw_step_validate(contract) |>
    tw_step_publish("risk.validated")
  list(
    root = root,
    lake = lake,
    path = path,
    good = good,
    write = write,
    contract = contract,
    pipeline = pipeline
  )
}
fixture_cleanup <- function(f) {
  tw_disconnect_lake(f$lake)
  unlink(f$root, recursive = TRUE)
}
reserve_metric <- function(product = "risk.validated") {
  tw_metric(
    "risk.reserve",
    product,
    expr = sum(reserve, na.rm = TRUE),
    dimensions = "company",
    time_column = "date",
    unit = "EUR",
    owner = "Risk",
    description = "Sum of reserves at one date",
    approved = TRUE,
    code_version = "metric-v1"
  )
}
