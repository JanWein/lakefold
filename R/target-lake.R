#' Choose governed lake storage for a composed product
#'
#' A folder path opens local DuckDB storage. Pass [dl_config()] for DuckLake,
#' S3 or PostgreSQL catalog configuration, or reuse an open lake. Connections
#' supplied by the caller remain caller-owned. The adapter compiles to the
#' existing immutable landing, candidate and publication transaction.
#' @param destination Folder path, connected lake, or lake configuration.
#' @param partition_by Optional columns identifying complete partitions to
#'   replace. Retained partitions are included in the final quality gate.
#' @param layer Publication layer in the lake configuration.
#' @returns A target accepted by [dl_add_target()] or [dl_publish()].
#' @export
#' @examples
#' dl_product("orders") |>
#'   dl_add_source(data.frame(id = 1:2)) |>
#'   dl_add_target(dl_target_lake("reporting-lake"))
dl_target_lake <- function(
  destination = "lakefold",
  partition_by = character(),
  layer = "validated"
) {
  if (is.character(destination)) {
    destination <- absolute_path(destination)
  }
  if (
    !is.character(destination) &&
      !inherits(destination, c("dl_lake", "dl_config"))
  ) {
    abort("destination must be a folder, dl_config() or an open lake.")
  }
  invisible(lapply(partition_by, column_name))
  if (anyDuplicated(partition_by)) {
    abort("Partition columns must be unique.")
  }
  ident(layer)
  structure(
    list(destination = destination, partition_by = partition_by, layer = layer),
    class = "dl_lake_target"
  )
}

normalize_target <- function(target) {
  if (is.character(target) || inherits(target, c("dl_lake", "dl_config"))) {
    return(dl_target_lake(target))
  }
  target
}

#' @export
dl_inspect.dl_lake_target <- function(x, ...) {
  config <- if (inherits(x$destination, "dl_lake")) {
    x$destination$config
  } else {
    x$destination
  }
  list(
    type = if (inherits(config, "dl_config")) config$backend else "local lake",
    layer = x$layer,
    partition_by = x$partition_by
  )
}
#' @export
dl_check_component.dl_lake_target <- function(x, ...) {
  need("duckdb")
  if (utils::packageVersion("duckdb") < "1.5.5") {
    abort("Lake storage requires duckdb >= 1.5.5.")
  }
  if (inherits(x$destination, "dl_lake")) {
    assert_writable(x$destination)
  }
  config <- if (inherits(x$destination, "dl_lake")) {
    x$destination$config
  } else {
    x$destination
  }
  if (inherits(config, "dl_config")) {
    if (isTRUE(config$read_only)) {
      abort("The publication target is read-only.", "dl_read_only")
    }
    if (!all(c("raw", x$layer) %in% config$layers)) {
      abort(
        "The target configuration must include raw and the publication layer."
      )
    }
  }
  invisible(x)
}

#' @export
dl_execute_target.dl_lake_target <- function(
  target,
  product,
  business_date = NA_character_,
  notify = NULL,
  cache = FALSE,
  ...
) {
  rlang::check_dots_empty()
  flag(cache, "cache")
  if (cache && is.null(product$code_version)) {
    abort(
      "Supply code_version in dl_product() before enabling cache; callbacks are re-evaluated by default."
    )
  }
  lake <- target$destination
  own <- !inherits(lake, "dl_lake")
  if (own) {
    lake <- if (inherits(lake, "dl_config")) dl_connect(lake) else dl_open(lake)
    on.exit(dl_close(lake), add = TRUE)
  }
  assert_writable(lake)
  definition <- dl_inspect(product)
  definition$status <- NULL
  definition$target <- NULL
  definition$source$rows <- NULL
  version <- if (product$automatic_version) {
    paste0("auto-", fingerprint(definition))
  } else {
    product$version
  }
  code <- product$code_version %||% "unversioned-no-cache"
  record <- c(list(kind = "composed_product"), definition)
  record$version <- version
  dl_register(lake, record)
  if (!is.null(product$contract)) {
    dl_register(lake, product$contract)
  }
  source <- product$source
  if (!inherits(source, "dl_source")) {
    data <- frame_result(dl_read_source(source), "The source")
    parent <- file.path(lake$config$landing, ".lakefold-staging")
    dir.create(parent, recursive = TRUE, showWarnings = FALSE)
    slot <- file.path(parent, product$id)
    if (!dir.create(slot, showWarnings = FALSE)) {
      abort(
        "Staging already exists for this asset. Check for a live or interrupted ingest before removing it."
      )
    }
    on.exit(unlink(slot, recursive = TRUE), add = TRUE)
    writeLines(jencode(writer_identity()), file.path(slot, "writer.json"))
    path <- file.path(slot, "delivery.rds")
    saveRDS(as.data.frame(data), path, compress = FALSE, version = 3)
    source <- dl_source(
      paste0(product$id, ".source"),
      path,
      readRDS,
      version = version
    )
  } else {
    source$version <- version
  }
  contract <- if (is.null(product$contract)) {
    structure(
      list(
        id = paste0(product$id, ".schema"),
        version = "inferred",
        kind = "contract",
        owner = "",
        producer = "",
        columns = NULL,
        rules = product$quality,
        automatic_schema = TRUE
      ),
      class = "dl_contract"
    )
  } else {
    combine_quality(product$contract, product$quality)
  }
  pipeline <- dl_pipeline(
    paste0(product$id, ".compose"),
    lake,
    version = version,
    code_version = code
  ) |>
    dl_step_land(source) |>
    dl_step_extract()
  for (name in names(product$transforms)) {
    step <- local({
      implementation <- product$transforms[[name]]
      label <- name
      function(data) {
        apply_product_transform(implementation, dl_collect(data), label)
      }
    })
    pipeline <- dl_step_transform(pipeline, step, name)
  }
  pipeline <- pipeline |>
    dl_step_validate(contract) |>
    dl_step_publish(
      product$id,
      mode = if (length(target$partition_by)) {
        "replace_partition"
      } else {
        "replace"
      },
      partition_by = target$partition_by,
      layer = target$layer
    )
  pipeline$composition <- definition
  pipeline$infer_contract <- is.null(product$contract)
  # Runtime-only closure; excluded from persisted specification and fingerprints.
  attr(pipeline, "dl_resolve_contract") <- function(data) {
    resolve_product_contract(lake, product, data)
  }
  result <- dl_run(
    pipeline,
    lake,
    business_date = business_date,
    notify = notify,
    cache = if (cache) "current" else FALSE,
    stop_on_failure = FALSE
  )
  run <- dl_registry(lake, "runs")
  run <- run[run$run_id == result$run_id, ]
  result$started_at <- run$started_at[[1]]
  result$finished_at <- run$finished_at[[1]]
  result$backend <- lake$config$backend
  result$output_config <- lake$config
  if (!own) {
    result$output_lake <- lake
  }
  result$asset <- product$id
  result$inputs <- metadata_filter(lake, "inputs", run_id = result$run_id)
  if (result$status %in% c("published", "cached")) {
    if (is.null(result$quality)) {
      result$quality <- dl_quality(lake, run_id = result$run_id)
    }
    table <- dl_tbl(lake, product$id, result$release_id)
    result$outputs <- list(asset = product$id, release_id = result$release_id)
    result$metadata <- list(
      schema = infer_column_types(table),
      rows = count_rows(table),
      lineage = metadata_filter(lake, "lineage_edges", run_id = result$run_id)
    )
  }
  result
}

resolve_product_contract <- function(lake, product, data) {
  definitions <- query(
    lake,
    paste(
      "SELECT DISTINCT a.definition FROM",
      meta(lake, "assets"),
      "a JOIN",
      meta(lake, "runs"),
      "r ON a.fingerprint = r.definition_hash AND a.id = r.pipeline",
      "WHERE a.kind = 'pipeline' AND r.asset = ?"
    ),
    list(product$id)
  )
  for (json in definitions$definition) {
    definition <- jdecode(json)
    prior <- definition$steps$validate
    if (!isTRUE(prior$automatic_schema)) {
      abort(
        "This asset uses an explicit contract. Add it with dl_add_contract() to keep its checks active."
      )
    }
    old_rules <- vapply(prior$rules, `[[`, character(1), "name")
    current_rules <- vapply(product$quality, `[[`, character(1), "name")
    if (!all(old_rules %in% current_rules)) {
      abort(
        "This asset has quality rules. Keep them in dl_add_quality() or use an explicit, versioned contract change."
      )
    }
  }
  release <- tryCatch(
    resolve_release(lake, product$id),
    dl_no_release = function(e) NULL
  )
  columns <- automatic_types(infer_column_types(data))
  if (!is.null(release)) {
    ref <- strsplit(release$contract[[1]], "@", fixed = TRUE)[[1]]
    previous <- query(
      lake,
      paste(
        "SELECT definition, fingerprint FROM",
        meta(lake, "assets"),
        "WHERE kind = 'contract' AND id = ? AND version = ?"
      ),
      as.list(ref)
    )
    if (nrow(previous) != 1L) {
      abort("Published contract metadata is missing.")
    }
    saved <- jdecode(previous$definition[[1]])
    if (!identical(fingerprint(saved), previous$fingerprint[[1]])) {
      abort(
        "Published contract metadata does not match its registered definition."
      )
    }
    if (!isTRUE(saved$automatic_schema)) {
      abort(
        "This asset uses an explicit contract. Add it with dl_add_contract()."
      )
    }
    columns <- automatic_types(unlist(saved$columns, use.names = TRUE))
  }
  combine_quality(automatic_schema(product$id, columns), product$quality)
}
