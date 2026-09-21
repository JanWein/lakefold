measure_set <- function(
  x,
  metrics,
  by,
  at,
  release,
  filters,
  params,
  record,
  period
) {
  rlang::local_error_call(rlang::caller_env())
  if (
    !is.list(metrics) ||
      !length(metrics) ||
      !all(vapply(metrics, inherits, logical(1), "dr_metric"))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "metrics must be a nonempty list of metric definitions."
    )
  }
  labels <- names(metrics) %||% vapply(metrics, `[[`, character(1), "id")
  if (anyNA(labels) || any(!nzchar(labels)) || anyDuplicated(labels)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric names must be nonmissing, nonempty and unique."
    )
  }
  reserved <- c(".metric", ".period", ".unit", "value")
  if (any(by %in% reserved)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Grouping columns cannot use .metric, .period, .unit or value."
    )
  }
  if (!is.null(at) && (!length(at) || anyNA(at) || anyDuplicated(at))) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "at must contain unique, nonmissing dates and cannot be empty."
    )
  }
  periods <- if (period == "each" && !is.null(at)) {
    lapply(seq_along(at), function(i) at[i])
  } else {
    list(at)
  }
  if (
    inherits(x, "dr_run_result") &&
      x$status %in% c("published", "cached") &&
      !(inherits(x$output_lake, "dr_lake") && DBI::dbIsValid(x$output_lake$con))
  ) {
    source <- dataraft.core::normalize_result_source(x)
    if (
      inherits(source, "dr_release_source") &&
        inherits(source$lake, "dr_config")
    ) {
      owned <- dataraft.lake::dr_connect_lake(source$lake, read_only = TRUE)
      on.exit(dataraft.lake::dr_disconnect_lake(owned), add = TRUE)
      x$output_lake <- owned
    }
  }
  results <- list()
  metadata <- list()
  for (i in seq_along(metrics)) {
    for (j in seq_along(periods)) {
      value <- dr_measure(
        x,
        metrics[[i]],
        by = by,
        at = periods[[j]],
        release = release,
        filters = filters,
        params = params,
        record = record
      )
      if (!setequal(names(value), c(by, "value"))) {
        dataraft.core::abort(
          subclass = "dataraft_error_metrics",
          "Batch metrics must return grouping columns and one value column."
        )
      }
      key <- paste0(i, ":", j)
      results[[key]] <- value
      metadata[[key]] <- list(
        metric = labels[[i]],
        period = periods[[j]],
        period_class = class(periods[[j]]),
        mode = period,
        unit = metrics[[i]]$unit
      )
    }
  }
  attr(results, "dr_set_metadata") <- metadata
  attr(results, "dr_set_hash") <- measurement_set_hash(results)
  class(results) <- c("dr_measurement_set", "list")
  results
}


measurement_set_hash <- function(x) {
  rlang::local_error_call(rlang::caller_env())
  dataraft.core::report_fingerprint(list(
    names = names(x),
    metadata = attr(x, "dr_set_metadata"),
    results = lapply(x, function(value) {
      list(manifest = attr(value, "dr_manifest"), values = as.data.frame(value))
    })
  ))
}


validate_measurement_set <- function(x) {
  rlang::local_error_call(rlang::caller_env())
  if (
    !length(x) || !identical(attr(x, "dr_set_hash"), measurement_set_hash(x))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Measurement set changed after calculation."
    )
  }
  invisible(x)
}


#' @rdname dr_measure
#' @param ... Reserved for future extensions.
#' @export
collect.dr_measurement_set <- function(x, ...) {
  rlang::check_dots_empty()
  validate_measurement_set(x)
  measurement_set_table(x, attr(x, "dr_set_metadata"))
}


measurement_set_table <- function(x, metadata) {
  rlang::local_error_call(rlang::caller_env())
  rows <- lapply(seq_along(x), function(i) {
    value <- tibble::as_tibble(x[[i]])
    attr(value, "dr_manifest") <- NULL
    attr(value, "dr_quality_reference") <- NULL
    value$.metric <- metadata[[i]]$metric
    value$.period <- rep(list(metadata[[i]]$period), nrow(value))
    value$.unit <- metadata[[i]]$unit
    by <- attr(x[[i]], "dr_manifest")$by
    value[c(by, ".metric", ".period", ".unit", "value")]
  })
  integer64 <- vapply(
    rows,
    function(row) inherits(row$value, "integer64"),
    logical(1)
  )
  ordinary_numeric <- vapply(
    rows,
    function(row) {
      is.numeric(row$value) && !is.object(row$value)
    },
    logical(1)
  )
  if (any(integer64) && any(ordinary_numeric)) {
    dataraft.core::need("bit64")
    limit <- bit64::as.integer64("9007199254740992")
    for (i in which(integer64)) {
      value <- rows[[i]]$value
      if (any(value > limit | value < -limit, na.rm = TRUE)) {
        dataraft.core::abort(
          subclass = "dataraft_error_metrics",
          paste(
            "These metrics mix decimal values with integers outside the exact numeric range.",
            "Collect the individual metric results separately to preserve their precision."
          )
        )
      }
      rows[[i]]$value <- as.double(as.character(value))
    }
  }
  dplyr::bind_rows(rows)
}


#' @rdname dr_measure
#' @export
print.dr_measurement_set <- function(x, ...) {
  validate_measurement_set(x)
  by <- attr(x[[1L]], "dr_manifest")$by
  cat(
    if (length(by)) {
      paste0("Grouped by: ", paste(by, collapse = ", "))
    } else {
      "Overall total (no grouping)"
    },
    "\n",
    sep = ""
  )
  print(collect.dr_measurement_set(x), ...)
  invisible(x)
}


report_connection <- function(lake, read_only) {
  rlang::local_error_call(rlang::caller_env())
  if (inherits(lake, "dr_config")) {
    if (!read_only && isTRUE(lake$read_only)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "This lake configuration is read-only."
      )
    }
    return(dataraft.lake::dr_connect_lake(lake, read_only = read_only))
  }
  if (is.character(lake) && length(lake) == 1L && !is.na(lake)) {
    if (!file.exists(file.path(lake, "dataraft.json"))) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Reports require an existing local lake folder."
      )
    }
    return(dataraft.lake::dr_open_lake(lake, read_only = read_only))
  }
  dataraft.core::abort(
    subclass = "dataraft_error_metrics",
    "lake must be a connected lake, lake configuration or local lake folder."
  )
}


measurement_report_destination <- function(results) {
  rlang::local_error_call(rlang::caller_env())
  references <- lapply(results, function(x) {
    ref <- attr(x, "dr_quality_reference")
    manifest <- attr(x, "dr_manifest")
    if (
      !is.list(ref) ||
        !inherits(ref$config, "dr_config") ||
        !identical(ref$asset, manifest$product) ||
        !identical(ref$release, manifest$release_id)
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Report destination cannot be inferred. Supply to explicitly."
      )
    }
    ref
  })
  configs <- lapply(references, `[[`, "config")
  if (!all(vapply(configs, identical, logical(1), configs[[1]]))) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Results refer to different lakes. Supply to explicitly."
    )
  }
  borrowed <- references[[1]]$lake
  if (
    inherits(borrowed, "dr_lake") &&
      DBI::dbIsValid(borrowed$con) &&
      identical(borrowed$config, configs[[1]])
  ) {
    return(borrowed)
  }
  configs[[1]]
}
