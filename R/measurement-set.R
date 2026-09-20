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
  if (
    !is.list(metrics) ||
      !length(metrics) ||
      !all(vapply(metrics, inherits, logical(1), "tw_metric"))
  ) {
    abort("metrics must be a nonempty list of metric definitions.")
  }
  labels <- names(metrics) %||% vapply(metrics, `[[`, character(1), "id")
  if (anyNA(labels) || any(!nzchar(labels)) || anyDuplicated(labels)) {
    abort("Metric names must be nonmissing, nonempty and unique.")
  }
  reserved <- c(".metric", ".period", ".unit", "value")
  if (any(by %in% reserved)) {
    abort("Grouping columns cannot use .metric, .period, .unit or value.")
  }
  if (!is.null(at) && (!length(at) || anyNA(at) || anyDuplicated(at))) {
    abort("at must contain unique, nonmissing dates and cannot be empty.")
  }
  periods <- if (period == "each" && !is.null(at)) {
    lapply(seq_along(at), function(i) at[i])
  } else {
    list(at)
  }
  if (
    inherits(x, "tw_run_result") &&
      !(inherits(x$output_lake, "tw_lake") && DBI::dbIsValid(x$output_lake$con))
  ) {
    source <- normalize_result_source(x)
    if (
      inherits(source, "tw_release_source") &&
        inherits(source$lake, "tw_config")
    ) {
      owned <- connect_lake(source$lake, read_only = TRUE)
      on.exit(disconnect_lake(owned), add = TRUE)
      x$output_lake <- owned
    }
  }
  results <- list()
  metadata <- list()
  for (i in seq_along(metrics)) {
    for (j in seq_along(periods)) {
      value <- measure(
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
        abort(
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
  attr(results, "tw_set_metadata") <- metadata
  attr(results, "tw_set_hash") <- measurement_set_hash(results)
  class(results) <- c("tw_measurement_set", "list")
  results
}

measurement_set_hash <- function(x) {
  fingerprint(list(
    names = names(x),
    metadata = attr(x, "tw_set_metadata"),
    results = lapply(x, function(value) {
      list(manifest = attr(value, "tw_manifest"), values = as.data.frame(value))
    })
  ))
}

validate_measurement_set <- function(x) {
  if (
    !length(x) || !identical(attr(x, "tw_set_hash"), measurement_set_hash(x))
  ) {
    abort("Measurement set changed after calculation.")
  }
  invisible(x)
}

#' @rdname measure
#' @param ... Reserved for future extensions.
#' @export
collect.tw_measurement_set <- function(x, ...) {
  rlang::check_dots_empty()
  validate_measurement_set(x)
  measurement_set_table(x, attr(x, "tw_set_metadata"))
}

measurement_set_table <- function(x, metadata) {
  rows <- lapply(seq_along(x), function(i) {
    value <- tibble::as_tibble(x[[i]])
    attr(value, "tw_manifest") <- NULL
    value$.metric <- metadata[[i]]$metric
    value$.period <- rep(list(metadata[[i]]$period), nrow(value))
    value$.unit <- metadata[[i]]$unit
    by <- attr(x[[i]], "tw_manifest")$by
    value[c(by, ".metric", ".period", ".unit", "value")]
  })
  dplyr::bind_rows(rows)
}

#' @rdname measure
#' @export
print.tw_measurement_set <- function(x, ...) {
  cat("<tw_measurement_set> ", length(x), " pinned calculations\n", sep = "")
  print(collect.tw_measurement_set(x), ...)
  invisible(x)
}

report_connection <- function(lake, read_only) {
  if (inherits(lake, "tw_config")) {
    if (!read_only && isTRUE(lake$read_only)) {
      abort("This lake configuration is read-only.")
    }
    return(connect_lake(lake, read_only = read_only))
  }
  if (is.character(lake) && length(lake) == 1L && !is.na(lake)) {
    if (!file.exists(file.path(lake, "tidyweave.json"))) {
      abort("Reports require an existing local lake folder.")
    }
    return(open_lake(lake, read_only = read_only))
  }
  abort(
    "lake must be a connected lake, lake configuration or local lake folder."
  )
}
