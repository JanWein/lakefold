#' Ingest an R data frame with an immutable delivery snapshot
#'
#' Use after reading Excel or fetching an API response with existing R tools.
#' Stores an RDS snapshot in landing, then uses the standard ingestion pipeline.
#' This records the received R object, not the original response or workbook.
#' Use [dl_source()] to preserve those original files.
#' @param lake Connected lake or [dl_config()].
#' @param data Data frame already in R memory.
#' @param contract Final candidate contract.
#' @param asset Governed output asset ID.
#' @param code_version Version of preparation code and dependencies.
#' @param version Ingestion and source definition version.
#' @param input_contract Optional contract to check before writing Raw.
#' @param ... Arguments forwarded to [dl_ingest()], such as business_date,
#'   layer, notify and stop_on_failure.
#' @returns A dl_run_result. Identical data and definitions can reuse a release.
#'   Connections opened here are closed on exit.
#' @export
#' @examples
#' root <- tempfile("lakefold-")
#' config <- dl_config(dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb")
#' contract <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' dl_ingest_data(config, data.frame(id = 1:3), contract, "orders",
#'   code_version = "v1", input_contract = contract)
#' unlink(root, recursive = TRUE)
dl_ingest_data <- function(
  lake,
  data,
  contract,
  asset,
  code_version,
  version = "1.0.0",
  input_contract = NULL,
  ...
) {
  if (!is.data.frame(data)) {
    abort("data must be a data frame.")
  }
  asset_id(asset)
  with_execution_lake(lake, function(con) {
    parent <- file.path(con$config$landing, ".lakefold-staging")
    dir.create(parent, recursive = TRUE, showWarnings = FALSE)
    slot <- file.path(parent, asset)
    if (!dir.create(slot, showWarnings = FALSE)) {
      abort(
        "Staging already exists for this asset. Check for a live or interrupted ingest before removing it."
      )
    }
    on.exit(unlink(slot, recursive = TRUE), add = TRUE)
    path <- file.path(slot, "delivery.rds")
    saveRDS(as.data.frame(data), path, compress = FALSE, version = 3)
    source <- dl_source(
      paste0(asset, ".data"),
      path,
      reader = readRDS,
      version = version,
      owner = contract$owner,
      description = "Snapshot of an R data frame; original transport is external."
    )
    dl_ingest(
      con,
      source,
      contract,
      asset,
      code_version = code_version,
      version = version,
      input_contract = input_contract,
      ...
    )
  })
}
