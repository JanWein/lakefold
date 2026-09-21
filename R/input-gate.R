#' Check a delivery before writing its raw table
#'
#' Add after extraction and before transformations. The source file is retained
#' in immutable landing even when the input gate blocks. The reader must return
#' a data frame, ensuring the checked values are the values subsequently written.
#' The mandatory candidate gate remains in place, including after partition
#' composition. A failed input gate is persisted with stage `"ingest"`.
#' @param pipeline Pipeline after `tw_step_extract()`.
#' @param contract Contract for the extracted input, possibly containing
#'   [tw_pointblank_checks()] rules. It can differ from the final product contract.
#' @returns The updated pipeline specification; no IO is performed.
#' @seealso `pipeline_ingest()`, [tw_validate()]
#' @examples
#' contract <- tw_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' pipeline <- tw_pipeline("orders.import", tw_lake_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   tw_step_land(tw_source_file("orders.file", "orders.csv", utils::read.csv)) |>
#'   tw_step_extract() |>
#'   tw_step_precheck(contract) |>
#'   tw_step_validate(contract) |>
#'   tw_step_publish("orders")
#' tw_plan(pipeline)
#' @noRd
tw_step_precheck <- function(pipeline, contract) {
  if (
    !inherits(pipeline, "tw_pipeline") ||
      !identical(names(pipeline$steps), c("land", "extract"))
  ) {
    abort(
      "Add the input gate immediately after extraction, before transforms.",
      "tw_pipeline_invalid"
    )
  }
  if (!inherits(contract, "tw_contract")) {
    abort("contract must be a contract.")
  }
  assert_contract_ready(contract)
  pipeline$steps$precheck <- contract
  pipeline
}
