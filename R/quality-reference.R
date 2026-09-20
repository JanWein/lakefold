#' Check that keys occur in another table
#'
#' The rule counts input rows without a matching reference key. Duplicate
#' reference keys do not multiply results. Missing key values fail by default,
#' including when the reference also contains a missing value. Use
#' `na_matches = "na"` to match missing values deliberately.
#'
#' Checks between lazy tables on the same database run as aggregate queries.
#' Moving reference keys between backends requires `copy = TRUE`; this may
#' collect all distinct reference keys and upload them to the input backend.
#' Only the mapped key columns are copied. No data rows are included in quality
#' evidence or contract metadata. References are resolved again on each run;
#' cached publication is unsuitable for a reference that can change separately.
#' @param reference A data frame, lazy table, source adapter, or zero-argument
#'   function returning one. Source adapters manage their own connections.
#' @param by Character vector of key columns, or a named vector mapping input
#'   columns to reference columns, for example `c(customer_id = "id")`.
#' @param name Name of the quality check.
#' @param severity,max_failure See [quality_rule()].
#' @param copy Explicitly permit moving reference keys between backends.
#' @param na_matches Whether missing values never match (`"never"`, default)
#'   or match other missing values (`"na"`).
#' @returns A quality rule accepted by [add_quality()] or [contract()].
#' @export
#' @examples
#' customers <- data.frame(id = c("a", "b"))
#' orders <- data.frame(customer_id = c("a", "missing", NA))
#' rule <- quality_reference(customers, c(customer_id = "id"))
#' run_quality(rule, orders)
quality_reference <- function(
  reference,
  by,
  name = "reference",
  severity = c("error", "warning"),
  max_failure = 0,
  copy = FALSE,
  na_matches = c("never", "na")
) {
  if (!is.character(by) || !length(by) || anyNA(by) || any(!nzchar(by))) {
    abort("by must name one or more reference key columns.")
  }
  if (is.null(names(by))) {
    names(by) <- by
  }
  if (
    anyNA(names(by)) ||
      any(!nzchar(names(by))) ||
      anyDuplicated(names(by)) ||
      anyDuplicated(unname(by))
  ) {
    abort("by must map unique input columns to unique reference columns.")
  }
  flag(copy, "copy")
  na_matches <- match.arg(na_matches)
  if (!is.data.frame(reference) && !is_lazy_table(reference)) {
    assert_component(reference, "read_source")
  }
  force(reference)
  rule <- quality_rule(
    name,
    function(data) {
      reference_quality_counts(data, reference, by, copy, na_matches)
    },
    severity = match.arg(severity),
    max_failure = max_failure,
    description = "Every input key must occur in the reference table."
  )
  rule$reference <- list(by = by, copy = copy, na_matches = na_matches)
  rule$dynamic_reference <- TRUE
  rule
}

reference_quality_counts <- function(data, reference, by, copy, na_matches) {
  if (!is.data.frame(reference) && !is_lazy_table(reference)) {
    reference <- read_source(reference)
  }
  input_columns <- names(table_prototype(data))
  reference_columns <- names(table_prototype(reference))
  missing_input <- setdiff(names(by), input_columns)
  missing_reference <- setdiff(unname(by), reference_columns)
  if (length(missing_input) || length(missing_reference)) {
    abort(paste0(
      "Reference check key columns are missing. Input: ",
      paste(missing_input, collapse = ", "),
      "; reference: ",
      paste(missing_reference, collapse = ", "),
      "."
    ))
  }
  reference <- dplyr::distinct(dplyr::select(
    reference,
    dplyr::all_of(unname(by))
  ))
  same <- tryCatch(dplyr::same_src(data, reference), error = function(e) FALSE)
  if (!same && !copy) {
    abort(
      "Reference keys are on another backend. Use copy = TRUE to permit moving them, or put both tables on the same backend."
    )
  }
  if (is.data.frame(data) && !is.data.frame(reference)) {
    reference <- dplyr::collect(reference)
  }
  failed <- dplyr::anti_join(
    data,
    reference,
    by = by,
    copy = copy,
    na_matches = na_matches
  )
  quality_counts(count_rows(failed), count_rows(data))
}
