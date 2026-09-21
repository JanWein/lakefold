#' Snapshot and publish one dbt relation as a governed release
#'
#' Requires a successful `dbt build` result containing the selected materialized
#' node. Copies the relation currently visible to this connection into an
#' immutable candidate, validates its contract, then commits the release marker.
#' Omit the contract for structural checks only: column names and R types are
#' inferred, while empty data and missing values are allowed. Business keys,
#' quality rules, ownership and freshness are never guessed. Later dbt builds
#' cannot change this snapshot. The dbt invocation is
#' recorded as provenance, not as proof that the live relation has not changed
#' since that build. Coordinate writers between build and publication.
#'
#' Each call validates a fresh snapshot; there is no cache based solely on a
#' dbt invocation ID. This prevents changed tables reusing stale quality
#' evidence.
#' This publishes one relation, not an atomic bundle of all dbt models.
#' @param lake Connected lake or [lake_config()] for the database used by dbt.
#'   Caller connections stay open; connections opened from a config are closed.
#' @param result Successful result from [dbt_build()].
#' @param model Exact dbt unique ID, such as `"model.shop.customer_revenue"`, or
#'   an unambiguous node name such as `"customer_revenue"`. Selection expressions
#'   and ambiguous names are rejected.
#' @param contract Optional contract for the copied candidate. An unnamed
#'   contract is scoped to the asset, as with [add_contract()].
#' @param asset Governed asset ID. Defaults to the selected node's name.
#' @param code_version Optional explicit code/dependency version. By default,
#'   hashes normalized manifest node, source and macro definitions and dbt version,
#'   excluding invocation IDs, timings and file locations. Include an explicit
#'   version when additional dependencies are not represented in the manifest.
#' @param version Optional publication definition version. Omitted versions are
#'   derived from the full publication definition, including its contract.
#' @param layer Configured destination layer. Defaults to `"marts"` if configured,
#'   otherwise `"products"`. Supply a layer explicitly when neither exists.
#' @param business_date Business date, separate from build or publication time.
#' @param notify Optional existing notification callback.
#' @param stop_on_failure Signal failure after persisting quality evidence.
#' @returns A `tw_run_result` accepted by [collect()]. `$outputs` identifies the
#'   exact database, schema, immutable table, asset and release. Use [source_release()]
#'   to compose a consumer workflow; a dbt model relation remains mutable.
#' @export
#' @examples
#' # After dbt_build() and reopening the lake connection:
#' # release <- dbt_publish(config, result, "customer_revenue")
#' # collect(release)
dbt_publish <- function(
  lake,
  result,
  model,
  contract = NULL,
  asset = NULL,
  code_version = NULL,
  version = NULL,
  layer = NULL,
  business_date = NA_character_,
  notify = NULL,
  stop_on_failure = TRUE
) {
  scalar(model, "model")
  flag(stop_on_failure, "stop_on_failure")
  if (
    !inherits(result, "tw_dbt_result") ||
      !isTRUE(result$success) ||
      !identical(result$command, "build") ||
      !identical(result$status, 0L) ||
      !is.data.frame(result$results) ||
      !all(c("unique_id", "status") %in% names(result$results)) ||
      !nrow(result$results) ||
      anyNA(result$results$status) ||
      anyNA(result$results$unique_id) ||
      anyDuplicated(result$results$unique_id) ||
      !all(result$results$status %in% c("success", "pass", "warn"))
  ) {
    abort(
      "Publication requires a successful dbt build result.",
      "tw_dbt_invalid"
    )
  }
  if (!is.null(result$artifact_hashes)) {
    dbt_verified_result(result)
  }
  model <- dbt_publication_model(result$manifest, model)
  node <- result$manifest$nodes[[model]]
  if (
    is.null(node) ||
      !node$resource_type %in% c("model", "seed", "snapshot") ||
      identical(node$config$materialized, "ephemeral") ||
      !model %in% result$results$unique_id[result$results$status == "success"]
  ) {
    abort(
      "The selected materialized node must have succeeded in this build.",
      "tw_dbt_invalid"
    )
  }
  invocation <- scalar(
    result$manifest$metadata$invocation_id,
    "dbt invocation ID"
  )
  if (
    !is.null(result$invocation_id) &&
      !identical(result$invocation_id, invocation)
  ) {
    abort(
      "The dbt result and manifest must describe the same invocation.",
      "tw_dbt_invalid"
    )
  }
  asset <- asset %||% node$name
  asset_id(asset)
  code_version <- code_version %||% dbt_publication_code(result$manifest)
  scalar(code_version, "code_version")
  if (!is.null(version)) {
    scalar(version, "version")
  }
  if (!is.null(contract)) {
    if (!inherits(contract, "tw_contract")) {
      abort("contract must be a contract.")
    }
    if (isTRUE(attr(contract, "tw_anonymous"))) {
      contract$id <- paste0(asset, ".contract")
      attr(contract, "tw_anonymous") <- NULL
    }
    assert_contract_ready(contract)
  }
  owned <- inherits(lake, "tw_config")
  if (owned) {
    lake <- connect_lake(lake)
    on.exit(close_lake(lake), add = TRUE)
  }
  assert_writable(lake)
  assert_table_asset(lake, asset)
  if (is.null(layer)) {
    layer <- intersect(c("marts", "products"), lake$config$layers)[1L]
    if (is.na(layer)) {
      abort("Configure a marts or products layer, or supply layer explicitly.")
    }
  }
  ident(layer)
  if (!layer %in% lake$config$layers) {
    abort("Publication layer is not configured.")
  }
  relation <- DBI::Id(
    catalog = scalar(node$database, "dbt database"),
    schema = scalar(node$schema, "dbt schema"),
    table = scalar(node$alias %||% node$name, "dbt relation")
  )
  if (is.null(contract)) {
    columns <- infer_column_types(dplyr::tbl(lake$con, relation))
    contract <- tidyweave::contract(
      paste0(asset, ".dbt_schema"),
      version = paste0(
        "auto-",
        fingerprint(list(
          columns = columns,
          required = character(),
          allow_empty = TRUE
        ))
      ),
      columns = columns,
      required = character(),
      allow_empty = TRUE,
      max_age_hours = NULL
    )
    contract$automatic_schema <- TRUE
  }
  definition <- list(
    id = asset,
    version = version,
    kind = "dbt_product",
    owner = contract$owner,
    description = contract$description,
    model = model,
    contract = contract,
    code_version = code_version,
    layer = layer,
    relation = list(
      database = node$database,
      schema = node$schema,
      table = node$alias %||% node$name
    )
  )
  if (is.null(version)) {
    definition$version <- paste0("auto-", fingerprint(definition))
  }
  register(lake, contract)
  register(lake, definition)
  dh <- fingerprint(definition)
  run <- new_run(lake, paste0(asset, ".dbt_publish"), asset, dh, code_version)
  started <- now()
  output_rows <- NULL
  output_schema <- NULL
  candidate <- NULL
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
      quality <- validate(candidate$data, contract)
      dbt_quality <- quality(result)
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
        output_rows <- count_rows(candidate$data)
        output_schema <- infer_column_types(candidate$data)
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
  out$asset <- asset
  out$output_config <- lake$config
  if (!owned) {
    out$output_lake <- lake
  }
  out$started_at <- started
  out$finished_at <- now()
  out$backend <- lake$config$backend
  out$inputs <- list(
    model = model,
    invocation_id = invocation,
    relation = definition$relation
  )
  out$metadata <- list(
    product = asset,
    model = model,
    invocation_id = invocation,
    code_version = code_version,
    version = definition$version,
    contract = canonical(contract),
    schema = output_schema,
    rows = output_rows
  )
  if (out$status %in% c("published", "cached")) {
    out$outputs <- list(
      type = "lake release",
      database = "lake",
      schema = layer,
      table = candidate$name,
      asset = asset,
      release_id = out$release_id
    )
  }
  if (stop_on_failure && !out$status %in% c("published", "cached")) {
    abort(
      "dbt snapshot publication failed; metadata persisted.",
      "tw_run_failed",
      result = out,
      parent = out$error
    )
  }
  out
}

dbt_publication_model <- function(manifest, model) {
  if (!is.list(manifest$nodes) || is.null(names(manifest$nodes))) {
    abort("The dbt result has no named manifest nodes.", "tw_dbt_invalid")
  }
  if (model %in% names(manifest$nodes)) {
    return(model)
  }
  matches <- names(manifest$nodes)[vapply(
    manifest$nodes,
    function(node) {
      identical(node$name, model) &&
        isTRUE(node$resource_type %in% c("model", "seed", "snapshot"))
    },
    logical(1)
  )]
  if (length(matches) != 1L) {
    abort(
      "Use an exact dbt unique ID or an unambiguous materialized node name.",
      "tw_dbt_invalid"
    )
  }
  matches[[1L]]
}

dbt_publication_code <- function(manifest) {
  fields <- c(
    "unique_id",
    "resource_type",
    "name",
    "package_name",
    "checksum",
    "raw_code",
    "compiled_code",
    "macro_sql",
    "config",
    "depends_on",
    "database",
    "schema",
    "alias",
    "identifier",
    "columns",
    "version"
  )
  definitions <- lapply(c("nodes", "sources", "macros"), function(kind) {
    lapply(manifest[[kind]], function(node) {
      node[intersect(fields, names(node))]
    })
  })
  names(definitions) <- c("nodes", "sources", "macros")
  definitions$dbt_version <- manifest$metadata$dbt_version
  definitions$adapter_type <- manifest$metadata$adapter_type
  paste0("dbt-", fingerprint(dbt_publication_canonical(definitions)))
}

dbt_publication_canonical <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  if (!is.null(names(x))) {
    x <- x[order(names(x))]
  }
  lapply(x, dbt_publication_canonical)
}

#' @rdname publish
#' @section Publishing a dbt model:
#' Use `dbt_project(path, lake = config) |> run() |> publish("model")` to
#' create an immutable, checked lake release. The destination is inferred from
#' the managed project's configuration. A model name must identify exactly one
#' materialized node that succeeded in this build. Artifact hashes and parsed
#' objects are checked again before publication. Pass `contract`, `asset`,
#' `layer` or other [dbt_publish()] options through `...`.
#'
#' Publication snapshots the current relation and checks that complete copy.
#' Build provenance does not prove a mutable relation is unchanged since dbt
#' finished. Coordinate writers between build and publication.
#' @export
publish.tw_dbt_result <- function(
  x,
  name = NULL,
  to = NULL,
  execution = NULL,
  ...
) {
  if (!is.null(execution)) {
    abort(
      "Execution defaults apply to R products. Configure dbt through its project and publication arguments."
    )
  }
  scalar(name, "model name")
  if (!isTRUE(x$success) || !identical(x$command, "build")) {
    abort(
      "Publication requires a successful dbt build result.",
      "tw_dbt_invalid"
    )
  }
  config <- x$project$lake %||% x$project$source_config
  lake <- to %||% config
  if (is.null(lake)) {
    abort(
      "An externally configured dbt project needs publish(..., to = lake_config(...)).",
      "tw_dbt_invalid"
    )
  }
  actual <- if (inherits(lake, "tw_lake")) lake$config else lake
  expected <- x$source_catalog %||%
    if (!is.null(config)) dbt_catalog_fingerprint(config)
  if (
    !is.null(expected) && !identical(dbt_catalog_fingerprint(actual), expected)
  ) {
    abort(
      "Publish to the same lake catalog used by this dbt build.",
      "tw_dbt_invalid"
    )
  }
  dbt_publish(lake, x, name, ...)
}

# Hashes protect on-disk artifacts; the parsed objects must describe them too.
dbt_verified_result <- function(result) {
  dbt_catalog_artifacts(result)
  parsed <- dbt_read_artifacts(result$artifacts_dir)
  if (
    !identical(parsed$manifest, result$manifest) ||
      !identical(parsed$results, result$results)
  ) {
    abort(
      "The dbt result changed after execution; use the original build result.",
      "tw_dbt_artifact_invalid"
    )
  }
  invisible(TRUE)
}
