#' Check a delivery before writing its raw table
#'
#' Add after extraction and before transformations. The source file is retained
#' in immutable landing even when the input gate blocks. The reader must return
#' a data frame, ensuring the checked values are the values subsequently written.
#' The mandatory candidate gate remains in place, including after partition
#' composition. A failed input gate is persisted with stage `"ingest"`.
#' @param pipeline Pipeline after [dl_step_extract()].
#' @param contract Contract for the extracted input, possibly containing
#'   [dl_pointblank()] rules. It can differ from the final product contract.
#' @returns The updated pipeline specification; no IO is performed.
#' @seealso [dl_ingest()], [dl_validate()]
#' @export
#' @examples
#' contract <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' pipeline <- dl_pipeline("orders.import", dl_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   dl_step_land(dl_source("orders.file", "orders.csv", utils::read.csv)) |>
#'   dl_step_extract() |>
#'   dl_step_precheck(contract) |>
#'   dl_step_validate(contract) |>
#'   dl_step_publish("orders")
#' dl_plan(pipeline)
dl_step_precheck <- function(pipeline, contract) {
  if (
    !inherits(pipeline, "dl_pipeline") ||
      !identical(names(pipeline$steps), c("land", "extract"))
  ) {
    abort(
      "Add the input gate immediately after extraction, before transforms.",
      "dl_pipeline_invalid"
    )
  }
  if (!inherits(contract, "dl_contract")) {
    abort("contract must be a dl_contract.")
  }
  assert_contract_ready(contract)
  pipeline$steps$precheck <- contract
  pipeline
}
