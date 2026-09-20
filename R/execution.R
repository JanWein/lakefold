#' Execute a product using a target adapter
#'
#' Most extensions only need [write_target()]: the default executor reads the
#' source, applies transforms, checks the candidate, then calls the writer.
#' Implement this generic only when execution needs different resource or
#' transaction semantics. The lake adapter compiles the product into the
#' existing governed ingestion lifecycle. Methods return `tw_run_result`.
#' @param target Target adapter, or `NULL` for in-memory execution.
#' @param product Validated product specification.
#' @param ... Execution options. Target adapters must reject unsupported options.
#' @returns A run result containing execution evidence and an output reference.
#' @examples
#' product <- product("orders") |> add_source(data.frame(id = 1:2))
#' tw_execute_target(NULL, validate(product))
#' @noRd
tw_execute_target <- function(target, product, ...) {
  UseMethod("tw_execute_target")
}

#' Write checked data using a target adapter
#'
#' The default executor calls this only after its contract and quality gate
#' pass. Methods receive a data frame and descriptive run context. A writer
#' must raise an error on failure and must never silently report success.
#' It owns its destination's atomicity and cleanup. Return a list describing
#' the output, without input rows, credentials or open connections. File and
#' database adapters can return paths or stable table identifiers.
#' @param target Target adapter. `NULL` retains data in the run result.
#' @param data Checked data frame or tibble.
#' @param context List with run ID, product ID, contract and metadata.
#' @param ... Reserved for adapter-specific options.
#' @returns A list describing the written output.
#' @export
#' @examples
#' write_target(NULL, data.frame(id = 1L), list(product = "orders"))
write_target <- function(target, data, context, ...) {
  UseMethod("write_target")
}
#' @export
write_target.NULL <- function(target, data, context, ...) {
  list(type = "memory", rows = count_rows(data))
}
#' @export
write_target.default <- function(target, data, context, ...) {
  abort("This target needs a write_target() method.")
}

#' Publish automatically generated metadata
#'
#' Catalog adapters receive product metadata after execution according to their
#' declared lifecycle support. A function is sufficient for a small integration.
#' Its return value is ignored. Metadata
#' delivery is separate from data publication: a catalog failure is recorded
#' as a warning and does not pretend that a committed data release was undone.
#'
#' [dbt_build()] and [dbt_test()] also accept a catalog function, or an S3
#' adapter with `capabilities(x)$metadata_inputs = "tw_dbt_result"`. These
#' receive the full dbt result, including local artifact paths, the manifest,
#' and dbt stdout/stderr. Callback authors control what is transmitted; these
#' diagnostics can contain SQL or database messages. Valid artifacts from
#' failed dbt tests can still be delivered without changing the dbt outcome.
#' [catalog_openmetadata_dbt()] delegates to the existing OpenMetadata ingestion
#' engine and returns a retryable, credential-free delivery receipt.
#' @param catalog Function or catalog adapter.
#' @param metadata Descriptive product run metadata without input rows or
#'   connections, or a `tw_dbt_result` for a catalog supporting dbt artifacts.
#' @param ... Reserved for adapter-specific options.
#' @returns The adapter's result; no specific value is required. Functions are
#'   called invisibly. The OpenMetadata dbt adapter returns a delivery receipt.
#' @export
#' @examples
#' received <- NULL
#' publish_metadata(function(metadata) received <<- metadata,
#'   list(product = "orders", rows = 2L))
publish_metadata <- function(catalog, metadata, ...) {
  UseMethod("publish_metadata")
}
#' @export
publish_metadata.function <- function(catalog, metadata, ...) {
  invisible(catalog(metadata))
}
#' @export
publish_metadata.default <- function(catalog, metadata, ...) {
  abort("This catalog needs a publish_metadata() method.")
}

#' Execute and publish a product with sensible local defaults
#'
#' `run()` executes a composed product in memory unless it has a target.
#' `publish()` adds a local lake target when none was supplied. A folder
#' string uses DuckDB; [target_lake()] accepts other lake configurations.
#' Both automatically validate the definition before source acquisition.
#' Use [collect()] to obtain the output as an ordinary tibble.
#' @param x Composed product, data frame, or successful dbt build.
#' @param name Product name for a data frame, or an exact or unambiguous model
#'   name for a dbt build. Omit it for an already named product.
#' @param to Optional target, replacing an already configured target. Defaults
#'   to the `tidyweave` folder in the working directory when the product has none.
#'   For dbt builds it defaults to the project's configured lake.
#' @param layer Optional publication layer for a lake target.
#' @param ... Execution options, including `stop_on_failure` and, for lake
#'   targets, `business_date`, `notify` and `cache`. dbt builds accept
#'   [dbt_publish()] options such as `contract`, `asset` and `layer`.
#' @returns A run result. An exception on failure includes `condition$result`.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-")
#' result <- product("orders") |>
#'   add_source(data.frame(id = 1:2)) |>
#'   publish(to = root)
#' collect(result)
#' unlink(root, recursive = TRUE)
publish <- function(x, name = NULL, to = NULL, ...) {
  UseMethod("publish")
}
#' @rdname publish
#' @export
publish.data.frame <- function(x, name = NULL, to = NULL, ...) {
  if (is.null(name)) {
    abort("Supply name when publishing a data frame, for example 'orders'.")
  }
  publish(product(name, x), to = to, ...)
}
#' @rdname publish
#' @export
publish.tw_product <- function(x, name = NULL, to = NULL, layer = NULL, ...) {
  if (!is.null(name)) {
    abort(
      "The product already has a name. Omit name or create product(name)."
    )
  }
  x <- editable_product(x)
  if (!is.null(to)) {
    x <- set_target(x, to)
  }
  if (is.null(x$target)) {
    x <- set_target(x, "tidyweave")
  }
  if (!is.null(layer)) {
    if (!inherits(x$target, "tw_lake_target")) {
      abort("layer is available only for lake publication targets.")
    }
    x$target$layer <- ident(layer)
  }
  run(x, ...)
}
#' @export
publish.default <- function(x, name = NULL, to = NULL, ...) {
  abort("Publish a product, data frame or successful dbt build.")
}

#' Collect the output of a successful run
#'
#' In-memory results retain their ordinary table. Lake results read their exact
#' published release, opening and closing a read-only connection if needed.
#' Custom target results retain their checked table in memory; their output
#' descriptor is also available in `$outputs`. For an append target this is
#' the submitted batch, not the complete mutable destination. The run metadata
#' distinguishes `submitted_rows` from output `rows`; candidate quality may
#' describe the complete destination including previously stored rows.
#' @param x Run result, data frame or lazy table.
#' @param ... Arguments passed to dplyr when collecting retained data. Lake
#'   results collect the complete pinned release and accept no extra arguments.
#' @returns An ordinary tibble. Failed or blocked runs cannot be collected.
#' @name collect
#' @importFrom dplyr collect
#' @export
#' @examples
#' product("orders") |> add_source(data.frame(id = 1:2)) |>
#'   run() |> collect()
dplyr::collect

#' @rdname collect
#' @export
collect.tw_run_result <- function(x, ...) {
  if (!x$status %in% c("completed", "published", "cached")) {
    abort(
      "This run has no successful output. Inspect status() and quality()."
    )
  }
  if (!is.null(x$data)) {
    return(tibble::as_tibble(dplyr::collect(x$data, ...)))
  }
  rlang::check_dots_empty()
  if (!is.null(x$output_lake) && DBI::dbIsValid(x$output_lake$con)) {
    return(read_release(x$output_lake, x$asset, x$release_id))
  }
  if (!is.null(x$output_config)) {
    config <- x$output_config
    config$read_only <- TRUE
    lake <- connect_lake(config)
    on.exit(close_lake(lake), add = TRUE)
    return(read_release(lake, x$asset, x$release_id))
  }
  abort(
    "This result has no output reference. Use read_release(lake, name, release_id) for older run results."
  )
}

#' @export
run.tw_product <- function(
  pipeline,
  lake = NULL,
  stop_on_failure = TRUE,
  evidence = getOption("tidyweave.evidence"),
  .context = NULL,
  ...
) {
  object <- pipeline
  if (!is.null(evidence)) {
    scalar(evidence, "evidence")
  }
  flag(stop_on_failure, "stop_on_failure")
  if (!is.null(lake)) {
    object <- set_target(object, lake)
  }
  object <- validate(object)
  context <- .context %||% new_product_context(evidence)
  if (exists(object$id, context$results, inherits = FALSE)) {
    return(get(object$id, context$results, inherits = FALSE))
  }
  attr(object, "tw_run_context") <- context
  started <- now()
  warnings <- list()
  result <- tryCatch(
    withCallingHandlers(
      tw_execute_target(object$target, object, ...),
      warning = function(w) {
        warnings[[length(warnings) + 1L]] <<- w
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      if (
        inherits(e$result, "tw_run_result") &&
          !inherits(e, "tw_dependency_failed")
      ) {
        return(e$result)
      }
      x <- run_result(uid(), "error")
      x$error <- e
      x
    }
  )
  if (
    !inherits(result, "tw_run_result") ||
      !is.character(result$run_id) ||
      length(result$run_id) != 1L ||
      is.na(result$run_id) ||
      !nzchar(result$run_id) ||
      !is.character(result$status) ||
      length(result$status) != 1L ||
      is.na(result$status) ||
      !result$status %in%
        c("completed", "published", "cached", "blocked", "error", "missing")
  ) {
    abort(
      "The target executor must return a tw_run_result with a run ID and supported status."
    )
  }
  result$asset <- object$id
  result$started_at <- result$started_at %||% started
  result$finished_at <- result$finished_at %||% now()
  result$backend <- result$backend %||% inspect(object$target)$type
  result$warnings <- result$warnings %||% character()
  result$warning_conditions <- warnings
  if (length(warnings)) {
    result$warnings <- c(
      result$warnings,
      paste0(
        "Execution produced ",
        length(warnings),
        " warning(s); inspect result$warning_conditions locally."
      )
    )
  }
  result$metadata <- c(
    result$metadata %||% list(),
    list(
      run_id = result$run_id,
      product = object$id,
      definition = inspect(object),
      code_version = object$code_version,
      started_at = result$started_at,
      finished_at = result$finished_at,
      status = result$status,
      backend = result$backend,
      quality = canonical(result$quality),
      inputs = result$inputs,
      outputs = result$outputs
    )
  )
  result$lifecycle <- tibble::tibble(
    state = c("defined", "validated", "planned", "running", result$status),
    at = c(
      NA_character_,
      started,
      started,
      result$started_at,
      result$finished_at
    )
  )
  result <- finalize_product_run(result, object, evidence)
  assign(object$id, result, context$results)
  if (length(result$warnings)) {
    rlang::warn(
      result$warnings,
      class = if (length(warnings)) {
        "tw_execution_warning"
      } else {
        "tw_catalog_warning"
      }
    )
  }
  if (
    stop_on_failure && !result$status %in% c("completed", "published", "cached")
  ) {
    abort(
      paste0(
        "Product `",
        object$id,
        "` ended with ",
        result$status,
        ". Inspect condition$result for execution evidence."
      ),
      "tw_run_failed",
      result = result,
      parent = result$error
    )
  }
  result
}

#' @export
#' @noRd
tw_execute_target.default <- function(target, product, ...) {
  rlang::check_dots_empty()
  run <- uid()
  started <- now()
  quality <- NULL
  input <- NULL
  transform_metadata <- list()
  out <- tryCatch(
    {
      acquired <- read_product_sources(product)
      data <- acquired$data
      input <- acquired$inputs
      for (name in names(product$transforms)) {
        data <- apply_product_transform(
          product$transforms[[name]],
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
      contract <- product_contract(product, data)
      quality <- validate(data, contract, keep_errors = TRUE)
      if (!quality_ok(quality)) {
        run_result(run, "blocked", quality = quality)
      } else {
        metadata <- list(
          product = product$id,
          transformations = transform_metadata,
          schema = infer_column_types(data),
          rows = count_rows(data),
          contract = canonical(contract),
          lineage = list(
            inputs = input,
            to = product$id
          )
        )
        output <- write_target(
          target,
          data,
          list(
            run_id = run,
            product = product$id,
            contract = contract,
            metadata = metadata
          )
        )
        if (!is.list(output)) {
          abort("The target writer must return an output descriptor list.")
        }
        if (!is.null(output$candidate_quality)) {
          if (
            !is.data.frame(output$candidate_quality) ||
              !quality_ok(output$candidate_quality)
          ) {
            abort(
              "The writer returned invalid or failing candidate quality evidence."
            )
          }
          quality <- output$candidate_quality
        }
        metadata$submitted_rows <- metadata$rows
        metadata$rows <- output$rows %||% metadata$rows
        metadata$schema <- output$schema %||% metadata$schema
        result <- run_result(
          run,
          if (is.null(target)) "completed" else "published",
          quality = quality
        )
        result$data <- data
        result$outputs <- output
        result$metadata <- metadata
        result
      }
    },
    error = function(e) {
      blocked <- inherits(e, "tw_target_quality_failed")
      if (blocked && !is.null(e$quality)) {
        quality <- e$quality
      }
      result <- run_result(
        run,
        if (blocked) "blocked" else "error",
        quality = quality
      )
      result$error <- e
      result
    }
  )
  out$started_at <- started
  out$finished_at <- now()
  out$inputs <- input
  out
}

apply_product_transform <- function(transform, data, name, sources = list()) {
  tryCatch(
    table_result(
      execute_transform(transform, data, sources = sources),
      paste0("Transformation `", name, "`")
    ),
    error = function(e) {
      abort(
        paste0("Transformation `", name, "` failed. ", conditionMessage(e)),
        "tw_transform_failed",
        parent = e
      )
    }
  )
}

product_contract <- function(product, data) {
  contract <- product$contract %||%
    automatic_schema(product$id, automatic_types(infer_column_types(data)))
  combine_quality(contract, product$quality)
}

combine_quality <- function(contract, rules) {
  if (!length(rules)) {
    return(contract)
  }
  contract$id <- paste0(contract$id, ".quality")
  contract$rules <- c(contract$rules, rules)
  contract$version <- paste0("checks-", fingerprint(contract))
  contract
}


new_product_context <- function(evidence = NULL) {
  context <- new.env(parent = emptyenv())
  context$results <- new.env(parent = emptyenv())
  context$sources <- list()
  context$evidence <- evidence
  context
}

result_data <- function(result) {
  if (!result$status %in% c("completed", "published", "cached")) {
    abort(
      "An upstream product did not complete successfully.",
      "tw_dependency_failed",
      result = result
    )
  }
  result$data %||% collect(result)
}

read_product_sources <- function(product, lake = NULL, on_input = NULL) {
  context <- attr(product, "tw_run_context") %||% new_product_context()
  sources <- product_sources(product)
  tables <- vector("list", length(sources))
  names(tables) <- names(sources)
  inputs <- vector("list", length(tables))
  archives <- list()
  for (i in seq_along(sources)) {
    name <- names(sources)[[i]]
    source <- sources[[i]]
    reference <- NULL
    reported <- FALSE
    if (inherits(source, "tw_product")) {
      upstream <- run(
        source,
        .context = context,
        evidence = context$evidence,
        stop_on_failure = FALSE
      )
      data <- result_data(upstream)
      reference <- list(
        asset = source$id,
        release_id = upstream$release_id,
        run_id = upstream$run_id
      )
      description <- list(type = "product", id = source$id)
    } else {
      match <- which(vapply(
        context$sources,
        function(item) {
          identical(item$source, source) && identical(item$lake, lake)
        },
        logical(1)
      ))
      if (length(match)) {
        item <- context$sources[[match[[1]]]]
        data <- item$data
        archive <- item$archive
      } else {
        archive <- NULL
        if (!is.null(lake) && inherits(source, "tw_source")) {
          landed <- land_source(lake, source)
          archive <- list(
            source = source$id,
            source_version = source$version,
            fingerprint = landed$hash,
            original_name = basename(source$path),
            landed_path = landed$uri,
            received_at = landed$received_at
          )
          if (!is.null(on_input)) {
            on_input(name, archive)
            reported <- TRUE
          }
          data <- source$reader(landed$path)
          if (
            !identical(
              digest::digest(
                file = landed$path,
                algo = "sha256",
                serialize = FALSE
              ),
              landed$hash
            )
          ) {
            abort("Reader modified immutable landing input.")
          }
          archive <- list(
            source = source$id,
            source_version = source$version,
            fingerprint = landed$hash,
            original_name = basename(source$path),
            landed_path = landed$uri,
            received_at = landed$received_at
          )
        } else {
          data <- if (identical(class(source), "tw_release_source")) {
            read_release_source(source, lake)
          } else {
            read_source(source)
          }
        }
        context$sources[[length(context$sources) + 1L]] <-
          list(source = source, lake = lake, data = data, archive = archive)
      }
      reference <- attr(data, "tw_input_reference")
      if (!is.null(archive)) {
        archives[[name]] <- archive
        if (!reported && !is.null(on_input)) on_input(name, archive)
      }
      description <- inspect(source)
      provenance <- attr(data, "tw_source_metadata")
      if (!is.null(provenance)) description$provenance <- provenance
    }
    data <- table_result(data, paste0("Source `", name, "`"))
    lazy <- is_lazy_table(data)
    pinned <- length(reference$release_id) == 1L &&
      !is.na(reference$release_id) &&
      nzchar(reference$release_id)
    if (!is.null(on_input) && !is.null(reference$asset)) {
      on_input(
        name,
        list(
          source = reference$asset,
          source_version = if (pinned) {
            reference$release_id
          } else {
            reference$run_id %||% "unversioned"
          },
          fingerprint = reference$hash %||%
            if (pinned) reference$release_id else reference$run_id %||% "",
          original_name = "",
          landed_path = "",
          received_at = now()
        )
      )
    }
    fingerprint <- if (pinned) {
      reference$release_id
    } else if (lazy) {
      digest::digest(description, algo = "sha256")
    } else {
      digest::digest(data, algo = "sha256")
    }
    inputs[[i]] <- tibble::tibble(
      name = name,
      source = list(description),
      rows = count_rows(data),
      fingerprint = fingerprint,
      hash_kind = if (pinned) {
        "release"
      } else if (lazy) {
        "definition"
      } else {
        "content"
      },
      asset = reference$asset %||% NA_character_,
      release_id = reference$release_id %||% NA_character_,
      run_id = reference$run_id %||% NA_character_
    )
    tables[[i]] <- data
  }
  primary <- tables[names(product$sources)]
  auxiliary <- lapply(names(product$transforms), function(step) {
    refs <- component_sources(product$transforms[[step]])
    stats::setNames(tables[transform_source_names(step, refs)], names(refs))
  })
  list(
    data = if (length(primary) == 1L) primary[[1]] else primary,
    transform_sources = stats::setNames(auxiliary, names(product$transforms)),
    inputs = dplyr::bind_rows(inputs),
    archives = archives
  )
}
