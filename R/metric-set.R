#' Define related metrics with shared defaults
#'
#' Captures named summary expressions without evaluating them. Returns an
#' ordinary named list of [tw_metric()] definitions for `tw_measure(metrics = ...)`.
#' Each id combines the product id and expression name, separated by a dot.
#' Business approval is explicit; exploratory definitions need no code version.
#' `dimensions` lists permitted grouping and filtering columns; it does not
#' choose a report layout. Select the grouping with `tw_measure(by = "company")`
#' or request an overall total explicitly with `tw_measure(by = character())`.
#' @param product Input asset id shared by all metrics.
#' @param ... Named tidy summary expressions, as in [dplyr::summarise()].
#' @param dimensions,time_column,owner,version,approved,code_version,na_policy
#'   Shared arguments passed to [tw_metric()].
#' @param time_behavior One shared `"stock"` or `"flow"` value, or a named
#'   vector covering every metric. Defaults to stock with a time column.
#' @param units One shared unit, or a named vector. Omitted names have no unit.
#' @return An ordinary named list of `metric` definitions.
#' @export
#' @examples
#' definitions <- tw_metric_set(
#'   "orders", total = sum(amount), count = dplyr::n(),
#'   dimensions = "company", units = c(total = "EUR")
#' )
tw_metric_set <- function(
  product,
  ...,
  dimensions = character(),
  time_column = NULL,
  time_behavior = if (is.null(time_column)) "flow" else "stock",
  units = "",
  owner = "",
  version = "1.0.0",
  approved = FALSE,
  code_version = NULL,
  na_policy = "reject"
) {
  expressions <- rlang::enquos(..., .ignore_empty = "none")
  labels <- names(expressions)
  if (!length(expressions) || any(!nzchar(labels)) || anyDuplicated(labels)) {
    abort("Supply uniquely named metric expressions.")
  }
  expand <- function(x, name, default = NULL) {
    if (!is.character(x) || anyNA(x)) {
      abort(paste(name, "must be character."))
    }
    if (is.null(names(x)) && length(x) == 1L) {
      return(rep(x, length(labels)))
    }
    if (
      is.null(names(x)) ||
        any(!nzchar(names(x))) ||
        anyDuplicated(names(x)) ||
        any(!names(x) %in% labels)
    ) {
      abort(paste(name, "must be a single value or uniquely named by metric."))
    }
    if (is.null(default) && !all(labels %in% names(x))) {
      abort(paste(name, "must cover every metric."))
    }
    values <- x[labels]
    values[is.na(values)] <- default
    unname(values)
  }
  behaviors <- expand(time_behavior, "time_behavior")
  unit_values <- expand(units, "units", "")
  stats::setNames(
    lapply(seq_along(expressions), function(i) {
      tw_metric(
        paste(product, labels[[i]], sep = "."),
        product,
        expr = !!expressions[[i]],
        dimensions = dimensions,
        time_column = time_column,
        time_behavior = behaviors[[i]],
        unit = unit_values[[i]],
        owner = owner,
        version = version,
        approved = approved,
        code_version = code_version,
        na_policy = na_policy
      )
    }),
    labels
  )
}
