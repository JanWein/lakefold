#' Execute a product using a target adapter
#'
#' Most extensions only need [dl_write_target()]: the default executor reads the
#' source, applies transforms, checks the candidate, then calls the writer.
#' Implement this generic only when execution needs different resource or
#' transaction semantics. The lake adapter compiles the product into the
#' existing governed ingestion lifecycle. Methods return `dl_run_result`.
#' @param target Target adapter, or `NULL` for in-memory execution.
#' @param product Validated product specification.
#' @param ... Execution options. Target adapters must reject unsupported options.
#' @returns A run result containing execution evidence and an output reference.
#' @export
#' @examples
#' product <- dl_product("orders") |> dl_add_source(data.frame(id = 1:2))
#' dl_execute_target(NULL, dl_validate(product))
dl_execute_target <- function(target, product, ...) {
  UseMethod("dl_execute_target")
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
#' dl_write_target(NULL, data.frame(id = 1L), list(product = "orders"))
dl_write_target <- function(target, data, context, ...) {
  UseMethod("dl_write_target")
}
#' @export
dl_write_target.NULL <- function(target, data, context, ...) {
  list(type = "memory", rows = nrow(data))
}
#' @export
dl_write_target.default <- function(target, data, context, ...) {
  abort("This target needs a dl_write_target() method.")
}

#' Publish automatically generated metadata
#'
#' Catalog adapters receive metadata after successful execution. A function is
#' sufficient for a small integration. Its return value is ignored. Metadata
#' delivery is separate from data publication: a catalog failure is recorded
#' as a warning and does not pretend that a committed data release was undone.
#' @param catalog Function or catalog adapter.
#' @param metadata Descriptive run metadata without input rows or connections.
#' @param ... Reserved for adapter-specific options.
#' @returns The adapter's result, invisibly; no specific value is required.
#' @export
#' @examples
#' received <- NULL
#' dl_publish_metadata(function(metadata) received <<- metadata,
#'   list(product = "orders", rows = 2L))
dl_publish_metadata <- function(catalog, metadata, ...) {
  UseMethod("dl_publish_metadata")
}
#' @export
dl_publish_metadata.function <- function(catalog, metadata, ...) {
  invisible(catalog(metadata))
}
#' @export
dl_publish_metadata.default <- function(catalog, metadata, ...) {
  abort("This catalog needs a dl_publish_metadata() method.")
}

#' Execute and publish a product with sensible local defaults
#'
#' `dl_run()` executes a composed product in memory unless it has a target.
#' `dl_publish()` adds a local lake target when none was supplied. A folder
#' string uses DuckDB; [dl_target_lake()] accepts other lake configurations.
#' Both automatically validate the definition before source acquisition.
#' Use [dl_collect()] to obtain the output as an ordinary tibble.
#' @param x Composed product, or a data frame for immediate publication.
#' @param name Product name; required for a data-frame expression.
#' @param to Optional target, replacing an already configured target. Defaults
#'   to the `lakefold` folder in the working directory when the product has none.
#' @param ... Execution options, including `stop_on_failure` and, for lake
#'   targets, `business_date`, `notify` and `cache`.
#' @returns A run result. An exception on failure includes `condition$result`.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("lakefold-")
#' result <- dl_product("orders") |>
#'   dl_add_source(data.frame(id = 1:2)) |>
#'   dl_publish(to = root)
#' dl_collect(result)
#' unlink(root, recursive = TRUE)
dl_publish <- function(x, name = NULL, to = NULL, ...) {
  if (is.data.frame(x)) {
    if (is.null(name)) {
      abort("Supply name when publishing a data frame, for example 'orders'.")
    }
    x <- dl_product(name) |> dl_add_source(x)
  } else if (!is.null(name)) {
    abort(
      "The product already has a name. Omit name or create dl_product(name)."
    )
  }
  x <- editable_product(x)
  if (!is.null(to)) {
    x <- dl_add_target(x, to)
  }
  if (is.null(x$target)) {
    x <- dl_add_target(x, "lakefold")
  }
  dl_execute(x, ...)
}

#' Collect the output of a successful run
#'
#' In-memory results retain their ordinary table. Lake results read their exact
#' published release, opening and closing a read-only connection if needed.
#' Custom target results retain their checked table in memory; their output
#' descriptor is also available in `$outputs`.
#' @param x Run result, data frame or lazy table.
#' @returns An ordinary tibble. Failed or blocked runs cannot be collected.
#' @export
#' @examples
#' dl_product("orders") |> dl_add_source(data.frame(id = 1:2)) |>
#'   dl_run() |> dl_collect()
dl_collect <- function(x) {
  if (is.data.frame(x)) {
    return(tibble::as_tibble(x))
  }
  if (inherits(x, "tbl_sql")) {
    return(dplyr::collect(x))
  }
  if (!inherits(x, "dl_run_result")) {
    abort("Use a run result, data frame or lazy table.")
  }
  if (!x$status %in% c("completed", "published", "cached")) {
    abort(
      "This run has no successful output. Inspect dl_status() and dl_quality()."
    )
  }
  if (!is.null(x$data)) {
    return(tibble::as_tibble(x$data))
  }
  if (!is.null(x$output_lake) && DBI::dbIsValid(x$output_lake$con)) {
    return(dl_read(x$output_lake, x$asset, x$release_id))
  }
  if (!is.null(x$output_config)) {
    config <- x$output_config
    config$read_only <- TRUE
    lake <- dl_connect(config)
    on.exit(dl_close(lake), add = TRUE)
    return(dl_read(lake, x$asset, x$release_id))
  }
  abort(
    "This result has no output reference. Use dl_read(lake, name, release_id) for older run results."
  )
}

#' @export
dl_execute.dl_product_spec <- function(
  object,
  lake = NULL,
  stop_on_failure = TRUE,
  ...
) {
  flag(stop_on_failure, "stop_on_failure")
  if (!is.null(lake)) {
    object <- dl_add_target(object, lake)
  }
  object <- dl_validate(object)
  started <- now()
  warnings <- list()
  result <- tryCatch(
    withCallingHandlers(
      dl_execute_target(object$target, object, ...),
      warning = function(w) {
        warnings[[length(warnings) + 1L]] <<- w
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      if (inherits(e$result, "dl_run_result")) {
        return(e$result)
      }
      x <- run_result(uid(), "error")
      x$error <- e
      x
    }
  )
  if (
    !inherits(result, "dl_run_result") ||
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
      "The target executor must return a dl_run_result with a run ID and supported status."
    )
  }
  result$asset <- object$id
  result$started_at <- result$started_at %||% started
  result$finished_at <- result$finished_at %||% now()
  result$backend <- result$backend %||% dl_inspect(object$target)$type
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
      product = object$id,
      definition = dl_inspect(object),
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
  if (result$status %in% c("completed", "published", "cached")) {
    for (i in seq_along(object$catalogs)) {
      tryCatch(
        dl_publish_metadata(object$catalogs[[i]], result$metadata),
        error = function(e) {
          result$warnings <<- c(
            result$warnings,
            paste0(
              "Catalog ",
              i,
              " metadata publication failed; data output remains available."
            )
          )
          result$catalog_errors[[as.character(i)]] <<- e
        }
      )
    }
  }
  if (length(result$warnings)) {
    rlang::warn(
      result$warnings,
      class = if (length(warnings)) {
        "dl_execution_warning"
      } else {
        "dl_catalog_warning"
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
      "dl_run_failed",
      result = result,
      parent = result$error
    )
  }
  result
}

#' @export
dl_execute_target.default <- function(target, product, ...) {
  rlang::check_dots_empty()
  run <- uid()
  started <- now()
  quality <- NULL
  input <- NULL
  out <- tryCatch(
    {
      data <- frame_result(dl_read_source(product$source), "The source")
      input <- list(
        source = dl_inspect(product$source),
        rows = nrow(data),
        hash = digest::digest(data, algo = "sha256")
      )
      for (name in names(product$transforms)) {
        data <- apply_product_transform(product$transforms[[name]], data, name)
      }
      contract <- product_contract(product, data)
      quality <- dl_validate(data, contract, keep_errors = TRUE)
      if (!quality_ok(quality)) {
        run_result(run, "blocked", quality = quality)
      } else {
        metadata <- list(
          product = product$id,
          schema = infer_column_types(data),
          rows = nrow(data),
          contract = canonical(contract),
          lineage = list(
            from = input$source,
            to = product$id,
            input_hash = input$hash
          )
        )
        output <- dl_write_target(
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
      result <- run_result(run, "error", quality = quality)
      result$error <- e
      result
    }
  )
  out$started_at <- started
  out$finished_at <- now()
  out$inputs <- input
  out
}

apply_product_transform <- function(transform, data, name) {
  tryCatch(
    frame_result(
      dl_execute_transform(transform, data),
      paste0("Transformation `", name, "`")
    ),
    error = function(e) {
      abort(
        paste0("Transformation `", name, "` failed. ", conditionMessage(e)),
        "dl_transform_failed",
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
