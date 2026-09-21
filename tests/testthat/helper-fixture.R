fixture <- function(backend = Sys.getenv("DATARAFT_TEST_BACKEND", "duckdb")) {
  testthat::skip_if_not_installed("duckdb")
  root <- tempfile("dataloom-test-")
  dir.create(root)
  lake <- dr_setup_lake(
    dr_registry_duckdb(file.path(root, "meta.duckdb")),
    dr_storage_local(file.path(root, "data")),
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
  contract <- dr_contract(
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
    rules = list(dr_quality_rule("nonnegative", function(x) {
      counts <- dplyr::collect(dplyr::summarise(
        x,
        n = dplyr::n(),
        failed = sum(as.integer(reserve < 0), na.rm = TRUE)
      ))
      dr_quality_counts(counts$failed, counts$n)
    }))
  )
  pipeline <- dr_pipeline("risk.import", lake, code_version = "test-code-v1") |>
    dr_step_land(dr_source_file("risk.source", path, reader = reader)) |>
    dr_step_extract() |>
    dr_step_validate(contract) |>
    dr_step_publish("risk.validated")
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
  dr_disconnect_lake(f$lake)
  unlink(f$root, recursive = TRUE)
}
reserve_metric <- function(product = "risk.validated") {
  dr_metric(
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
