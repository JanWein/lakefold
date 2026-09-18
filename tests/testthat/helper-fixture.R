fixture <- function(backend = Sys.getenv("DATALOOM_TEST_BACKEND", "duckdb")) {
  root <- tempfile("dataloom-test-"); dir.create(root)
  lake <- dl_setup(dl_catalog_duckdb(file.path(root, "meta.duckdb")), dl_storage_local(file.path(root, "data")),
    landing = file.path(root, "landing"), backend = backend)
  path <- file.path(root, "input.csv")
  good <- data.frame(id = c("a", "b"), company = c("Alpha", "Beta"), date = as.Date(c("2026-08-31", "2026-08-31")), reserve = c(100, 200))
  write <- function(data = good) utils::write.csv(data, path, row.names = FALSE)
  write()
  reader <- function(path) {
    x <- utils::read.csv(path, colClasses = c("character", "character", "Date", "numeric"))
    x
  }
  contract <- dl_contract("risk.contract", "1.0.0", "Risk", "Validated reserves", "One contract at a date",
    c(id = "character", company = "character", date = "Date", reserve = "numeric"), key = c("id", "date"),
    rules = list(dl_rule("nonnegative", function(x) {
      counts <- dplyr::collect(dplyr::summarise(x, n = dplyr::n(), failed = sum(as.integer(reserve < 0), na.rm = TRUE)))
      dl_quality_counts(counts$failed, counts$n)
    })))
  pipeline <- dl_pipeline("risk.import", lake, code_version = "test-code-v1") |>
    dl_step_land(dl_source("risk.source", path, reader = reader)) |>
    dl_step_extract() |> dl_step_validate(contract) |> dl_step_publish("risk.validated")
  list(root = root, lake = lake, path = path, good = good, write = write, contract = contract, pipeline = pipeline)
}
cleanup <- function(f) { dl_disconnect(f$lake); unlink(f$root, recursive = TRUE) }
reserve_metric <- function(product = "risk.validated") dl_metric("risk.reserve", product, expr = sum(reserve, na.rm = TRUE),
  dimensions = "company", time_column = "date", unit = "EUR", owner = "Risk", description = "Sum of reserves at one date",
  approved = TRUE, code_version = "metric-v1")
