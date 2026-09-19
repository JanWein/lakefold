#' Snapshot and publish one dbt relation as a governed release
#'
#' Requires a successful `dbt build` result containing the selected materialized
#' node. Copies the relation currently visible to this connection into an
#' immutable candidate, validates the supplied contract, then commits the
#' release
#' marker. Later dbt builds cannot change this snapshot. The dbt invocation is
#' recorded as provenance, not as proof that the live relation has not changed
#' since that build. Coordinate writers between build and publication.
#'
#' Each call validates a fresh snapshot; there is no cache based solely on a
#' dbt invocation ID. This prevents changed tables reusing stale quality
#' evidence.
#' This publishes one relation, not an atomic bundle of all dbt models.
#' @param lake Connected lake with the dbt relation attached.
#' @param result Successful result from [dl_dbt_build()].
#' @param model Exact dbt unique ID, such as `"model.shop.customer_revenue"`.
#' @param contract Contract for the copied candidate.
#' @param asset Governed asset ID.
#' @param code_version Version of publication code and all relevant
#'   dependencies.
#' @param version Publication definition version.
#' @param layer Configured destination layer.
#' @param business_date Business date, separate from build or publication time.
#' @param notify Optional existing notification callback.
#' @param stop_on_failure Signal failure after persisting quality evidence.
#' @returns A `dl_run_result`. Use [dl_tbl()] with its release ID for immutable
#'   consumption, and [dl_model()] for relationships between pinned releases.
#' @export
#' @examples
#' # After dl_dbt_build() and reopening the lake connection:
#' # release <- dl_dbt_publish(lake, result, "model.shop.customer_revenue",
#' #   contract, "shop.revenue", code_version = "v1")
#' # dl_tbl(lake, "shop.revenue", release$release_id)
dl_dbt_publish <- function(
  lake,
  result,
  model,
  contract,
  asset,
  code_version,
  version = "1.0.0",
  layer = "products",
  business_date = NA_character_,
  notify = NULL,
  stop_on_failure = TRUE
) {
  assert_lake(lake)
  asset_id(asset)
  scalar(model, "model")
  scalar(code_version, "code_version")
  scalar(version, "version")
  ident(layer)
  flag(stop_on_failure, "stop_on_failure")
  if (!inherits(contract, "dl_contract")) {
    abort("contract must be a dl_contract.")
  }
  assert_contract_ready(contract)
  if (!layer %in% lake$config$layers) {
    abort("Publication layer is not configured.")
  }
  if (
    !inherits(result, "dl_dbt_result") ||
      !isTRUE(result$success) ||
      !identical(result$command, "build") ||
      result$status != 0L ||
      !all(result$results$status %in% c("success", "pass", "warn"))
  ) {
    abort(
      "Publication requires a successful dbt build result.",
      "dl_dbt_invalid"
    )
  }
  node <- result$manifest$nodes[[model]]
  if (
    is.null(node) ||
      !node$resource_type %in% c("model", "seed", "snapshot") ||
      identical(node$config$materialized, "ephemeral") ||
      !model %in% result$results$unique_id[result$results$status == "success"]
  ) {
    abort(
      "The selected materialized node must have succeeded in this build.",
      "dl_dbt_invalid"
    )
  }
  invocation <- scalar(
    result$manifest$metadata$invocation_id,
    "dbt invocation ID"
  )
  relation <- DBI::Id(
    catalog = scalar(node$database, "dbt database"),
    schema = scalar(node$schema, "dbt schema"),
    table = scalar(node$alias %||% node$name, "dbt relation")
  )
  definition <- list(
    id = asset,
    version = version,
    kind = "dbt_product",
    owner = contract$owner,
    description = contract$description,
    model = model,
    contract = contract,
    code_version = code_version,
    layer = layer
  )
  dl_register(lake, contract)
  dl_register(lake, definition)
  dh <- fingerprint(definition)
  run <- new_run(lake, paste0(asset, ".dbt_publish"), asset, dh, code_version)
  out <- tryCatch(
    {
      ih <- fingerprint(list(
        invocation = invocation,
        model = model,
        snapshot = run,
        business_date = as.character(business_date)
      ))
      exec(
        lake,
        paste(
          "UPDATE",
          meta(lake, "runs"),
          "SET input_hash = ? WHERE run_id = ?"
        ),
        list(ih, run)
      )
      insert_meta(
        lake,
        "inputs",
        list(
          run_id = run,
          source = model,
          source_version = invocation,
          fingerprint = ih,
          original_name = "",
          landed_path = "",
          received_at = now(),
          business_date = as.character(business_date)
        )
      )
      pub <- list(asset = asset, mode = "replace", layer = layer)
      candidate <- compose_candidate(
        lake,
        dplyr::tbl(lake$con, relation),
        pub,
        run
      )
      quality <- dl_validate(candidate$data, contract)
      dbt_quality <- dl_quality(result)
      dbt_quality$failure_rate <- NULL
      quality <- dplyr::bind_rows(dbt_quality, quality)
      persist_quality(lake, run, contract, quality)
      if (!quality_ok(quality)) {
        finish_run(
          lake,
          run,
          "blocked",
          "dbt snapshot failed the publication contract."
        )
        emit_event(
          lake,
          run,
          asset,
          "quality_failed",
          contract$producer,
          "dbt snapshot publication blocked; inspect quality_results.",
          notify
        )
        run_result(run, "blocked", quality = quality)
      } else {
        publish_candidate(
          lake,
          run,
          pub,
          candidate,
          contract,
          quality,
          dh,
          ih,
          business_date,
          list(list(from_id = model, from_version = invocation))
        )
      }
    },
    error = function(e) {
      finish_run(lake, run, "error", "dbt snapshot publication failed.")
      emit_event(
        lake,
        run,
        asset,
        "run_error",
        contract$producer,
        "dbt snapshot publication failed; inspect the local error condition.",
        notify
      )
      x <- run_result(run, "error")
      x$error <- e
      x
    }
  )
  if (stop_on_failure && !out$status %in% c("published", "cached")) {
    abort(
      "dbt snapshot publication failed; metadata persisted.",
      "dl_run_failed",
      result = out,
      parent = out$error
    )
  }
  out
}
