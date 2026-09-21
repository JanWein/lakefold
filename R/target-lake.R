#' Choose governed lake storage for a composed product
#'
#' A folder path opens local DuckDB storage. Pass [tw_lake_config()] for DuckLake,
#' S3 or PostgreSQL catalog configuration, or reuse an open lake. Connections
#' supplied by the caller remain caller-owned. The adapter compiles to the
#' existing immutable landing, candidate and publication transaction.
#' @param destination Folder path, connected lake, or lake configuration.
#' @param partition_by Optional columns identifying complete partitions to
#'   replace. Retained partitions are included in the final quality gate.
#' @param layer Publication layer in the lake configuration.
#' @returns A target accepted by [tw_set_target()] or [tw_publish()].
#' @export
#' @examples
#' tw_product("orders") |>
#'   tw_add_source(data.frame(id = 1:2)) |>
#'   tw_set_target(tw_target_lake("reporting-lake"))
tw_target_lake <- function(
  destination = "tidyweave",
  partition_by = character(),
  layer = "validated"
) {
  if (is.character(destination)) {
    destination <- absolute_path(destination)
  }
  if (
    !is.character(destination) &&
      !inherits(destination, c("tw_lake", "tw_config"))
  ) {
    abort("destination must be a folder, tw_lake_config() or an open lake.")
  }
  invisible(lapply(partition_by, column_name))
  if (anyDuplicated(partition_by)) {
    abort("Partition columns must be unique.")
  }
  ident(layer)
  structure(
    list(destination = destination, partition_by = partition_by, layer = layer),
    class = "tw_lake_target"
  )
}

normalize_target <- function(target) {
  if (is.character(target) || inherits(target, c("tw_lake", "tw_config"))) {
    return(tw_target_lake(target))
  }
  target
}

#' @export
tw_inspect.tw_lake_target <- function(x, ...) {
  config <- if (inherits(x$destination, "tw_lake")) {
    x$destination$config
  } else {
    x$destination
  }
  list(
    type = if (inherits(config, "tw_config")) config$backend else "local lake",
    layer = x$layer,
    partition_by = x$partition_by
  )
}
#' @export
tw_check_component.tw_lake_target <- function(x, ...) {
  need("duckdb")
  if (utils::packageVersion("duckdb") < "1.5.5") {
    abort("Lake storage requires duckdb >= 1.5.5.")
  }
  if (inherits(x$destination, "tw_lake")) {
    assert_writable(x$destination)
  }
  config <- if (inherits(x$destination, "tw_lake")) {
    x$destination$config
  } else {
    x$destination
  }
  if (inherits(config, "tw_config")) {
    if (isTRUE(config$read_only)) {
      abort("The publication target is read-only.", "tw_read_only")
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
#' @noRd
tw_execute_target.tw_lake_target <- function(
  target,
  product,
  business_date = NA_character_,
  notify = NULL,
  cache = FALSE,
  previous = NULL,
  ...
) {
  rlang::check_dots_empty()
  flag(cache, "cache")
  if (cache && is.null(product$code_version)) {
    abort(
      "Supply code_version in tw_product() before enabling cache; callbacks are re-evaluated by default."
    )
  }
  rules <- c(product$contract$rules, product$quality)
  if (
    cache &&
      any(vapply(
        rules,
        function(rule) isTRUE(rule$dynamic_reference),
        logical(1)
      ))
  ) {
    abort(
      "Live reference checks cannot reuse cached releases. Use cache = FALSE."
    )
  }
  lake <- target$destination
  own <- !inherits(lake, "tw_lake")
  if (own) {
    lake <- if (inherits(lake, "tw_config")) {
      tw_connect_lake(lake)
    } else {
      tw_open_lake(lake)
    }
    on.exit(tw_close_lake(lake), add = TRUE)
  }
  assert_writable(lake)
  check_previous_release(lake, product$id, previous)
  assert_table_asset(lake, product$id)
  definition <- tw_inspect(product)
  definition$status <- NULL
  definition$target <- NULL
  definition$publication <- list(
    layer = target$layer,
    partition_by = target$partition_by
  )
  definition$sources <- lapply(definition$sources, function(x) {
    x$rows <- NULL
    x
  })
  version <- if (product$automatic_version) {
    paste0("auto-", fingerprint(definition))
  } else {
    product$version
  }
  code <- product$code_version %||% "unversioned-no-cache"
  record <- c(list(kind = "composed_product"), definition)
  record$version <- version
  tw_register(lake, record)
  if (!is.null(product$contract)) {
    tw_register(lake, product$contract)
  }
  run_id <- new_run(
    lake,
    paste0(product$id, ".compose"),
    product$id,
    fingerprint(record),
    code
  )
  acquired <- NULL
  extra_inputs <- list()
  record_input <- function(name, input) {
    extra_inputs[[name]] <<- input
    insert_meta(
      lake,
      "inputs",
      c(
        list(run_id = run_id),
        input,
        list(business_date = as.character(business_date))
      )
    )
  }
  result <- tryCatch(
    {
      single <- length(product$sources) == 1L
      source <- if (single) product$sources[[1]] else NULL
      transforms <- product$transforms
      transform_metadata <- list()
      auxiliary <- any(vapply(
        transforms,
        function(step) length(component_sources(step)) > 0L,
        logical(1)
      ))
      if (!single || !inherits(source, "tw_source") || auxiliary) {
        acquired <- read_product_sources(
          product,
          lake = lake,
          on_input = record_input
        )
        data <- acquired$data
        # Multiple inputs must be combined before they enter one publication.
        # The lake adapter is an explicit materialization boundary; native and
        # database targets preserve lazy tables through their transformations.
        if (!single || auxiliary) {
          for (name in names(transforms)) {
            data <- apply_product_transform(
              transforms[[name]],
              data,
              name,
              sources = acquired$transform_sources[[name]]
            )
            details <- attr(data, "tw_transform_metadata")
            if (!is.null(details)) {
              transform_metadata[[name]] <- details
            }
            attr(data, "tw_transform_metadata") <- NULL
          }
          data <- table_result(data, "The final transformation")
          transforms <- list()
        }
        data <- tw_collect(table_result(data, "The source"))
        parent <- file.path(lake$config$landing, ".tidyweave-staging")
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
        source <- tw_source_file(
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
          class = "tw_contract"
        )
      } else {
        combine_quality(effective_product_contract(product), product$quality)
      }
      pipeline <- tw_pipeline(
        paste0(product$id, ".compose"),
        lake,
        version = version,
        code_version = code
      ) |>
        tw_step_land(source) |>
        tw_step_extract()
      for (name in names(transforms)) {
        step <- local({
          implementation <- transforms[[name]]
          label <- name
          inputs <- acquired$transform_sources[[name]] %||% list()
          function(data) {
            out <- apply_product_transform(
              implementation,
              tw_collect(data),
              label,
              sources = inputs
            )
            details <- attr(out, "tw_transform_metadata")
            if (!is.null(details)) {
              transform_metadata[[label]] <<- details
            }
            attr(out, "tw_transform_metadata") <- NULL
            out
          }
        })
        pipeline <- pipeline_step_transform(pipeline, step, name)
      }
      pipeline <- pipeline |>
        tw_step_validate(contract) |>
        tw_step_publish(
          product$id,
          mode = if (length(target$partition_by)) {
            "replace_partition"
          } else {
            "replace"
          },
          partition_by = target$partition_by,
          layer = target$layer
        )
      attr(pipeline, "tw_product_inputs") <- extra_inputs
      attr(pipeline, "tw_run_id") <- run_id
      attr(pipeline, "tw_inputs_recorded") <- TRUE
      pipeline$composition <- definition
      pipeline$infer_contract <- is.null(product$contract)
      # Runtime-only closure; excluded from persisted specification and fingerprints.
      attr(pipeline, "tw_resolve_contract") <- function(data) {
        resolve_product_contract(lake, product, data)
      }
      tw_run(
        pipeline,
        lake,
        business_date = business_date,
        notify = notify,
        cache = if (cache) "current" else FALSE,
        stop_on_failure = FALSE
      )
    },
    error = function(e) {
      status <- if (inherits(e, "tw_missing_delivery")) "missing" else "error"
      finish_run(
        lake,
        run_id,
        status,
        "Product preparation or execution failed."
      )
      emit_event(
        lake,
        run_id,
        product$id,
        "run_error",
        product$contract$producer %||% "",
        "Product execution failed; inspect source availability and transformations.",
        notify
      )
      result <- run_result(run_id, status)
      result$error <- e
      result
    }
  )
  run <- tw_registry(lake, "runs")
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
  if (!is.null(acquired)) {
    result$source_inputs <- acquired$inputs
  }
  if (result$status %in% c("published", "cached")) {
    if (is.null(result$quality)) {
      result$quality <- tw_quality(lake, run_id = result$run_id)
    }
    table <- tw_tbl(lake, product$id, result$release_id)
    result$outputs <- list(asset = product$id, release_id = result$release_id)
    result$metadata <- list(
      transformations = transform_metadata,
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
        "This asset uses an explicit contract. Add it with tw_add_contract() to keep its checks active."
      )
    }
    old_rules <- vapply(prior$rules, `[[`, character(1), "name")
    current_rules <- vapply(product$quality, `[[`, character(1), "name")
    if (!all(old_rules %in% current_rules)) {
      abort(
        "This asset has quality rules. Keep them in tw_add_quality() or use an explicit, versioned contract change."
      )
    }
  }
  release <- tryCatch(
    resolve_release(lake, product$id),
    tw_no_release = function(e) NULL
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
        "This asset uses an explicit contract. Add it with tw_add_contract()."
      )
    }
    columns <- automatic_types(unlist(saved$columns, use.names = TRUE))
  }
  combine_quality(automatic_schema(product$id, columns), product$quality)
}
