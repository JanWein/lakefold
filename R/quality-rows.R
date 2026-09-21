#' Inspect rows failing a specific quality check
#'
#' Explicitly reads row data for local repair. Rows are never added to catalog
#' metadata or portable quality reports. Formula predicates are re-evaluated on
#' the retained candidate, so keep their captured constants unchanged. Required
#' values and duplicate keys are also supported. Aggregate and custom agent
#' checks do not necessarily identify rows and are rejected with an explanation.
#' Failed lake candidates remain available until cleanup removes them.
#' @param x A blocked run result, or a table to diagnose explicitly.
#' @param rule Check name from [tw_quality_report()], or a one-sided row formula.
#'   Omit it when the result has one failed check or a failed lookup. When
#'   several checks fail, the error lists the names to choose from.
#' @param contract Contract when supplying a table and a named check.
#' @param limit Maximum returned rows; `Inf` explicitly requests all rows.
#' @returns A tibble containing the affected rows, bounded by `limit`.
#' @export
#' @examples
#' orders <- tw_product("orders", data.frame(amount = c(10, -2))) |>
#'   tw_add_quality(list(positive = ~ amount >= 0))
#' failed <- tw_trial(orders, stop_on_failure = FALSE)
#' tw_quality_rows(failed, "positive")
tw_quality_rows <- function(x, rule = NULL, contract = NULL, limit = 100) {
  if (
    !is.numeric(limit) ||
      length(limit) != 1L ||
      is.na(limit) ||
      limit < 0 ||
      (is.finite(limit) && limit != floor(limit))
  ) {
    abort("limit must be a non-negative whole number or Inf.")
  }
  if (inherits(x, "tw_model_result")) {
    failed <- names(x$members)[vapply(
      x$members,
      function(m) {
        !m$status %in%
          c("completed", "published", "cached")
      },
      logical(1)
    )]
    if (is.null(rule) && length(failed) == 1L) {
      return(tw_quality_rows(x$members[[failed]], limit = limit))
    }
    if (!is.null(rule) && is.character(rule)) {
      selected <- names(x$members)[startsWith(
        rule,
        paste0(names(x$members), "/")
      )]
      if (length(selected) == 1L) {
        return(tw_quality_rows(
          x$members[[selected]],
          substring(rule, nchar(selected) + 2L),
          limit = limit
        ))
      }
    }
    abort(
      "Select a table/check from tw_quality_report(result); for relationships inspect result$error$checks."
    )
  }
  if (inherits(x, "tw_run_result")) {
    checks <- tw_quality(x)
    if (is.null(rule) && is.data.frame(checks)) {
      failed <- unique(checks$rule[!checks$status %in% c("passed", "warning")])
      if (length(failed) == 1L) {
        rule <- failed[[1L]]
      }
      if (length(failed) > 1L) {
        abort(paste0(
          "Several checks need attention: ",
          paste(failed, collapse = ", "),
          ". Select one with tw_quality_rows(result, rule = \"",
          failed[[1L]],
          "\")."
        ))
      }
    }
    diagnostic <- x$diagnostic
    if (is.null(diagnostic)) {
      condition <- x$error
      while (!is.null(condition) && is.null(diagnostic)) {
        diagnostic <- condition$diagnostic
        condition <- condition$parent
      }
    }
    if (is.null(diagnostic)) {
      abort(
        "No row diagnostic was retained. Supply the relevant table and contract explicitly."
      )
    }
    contract <- diagnostic$contract
    if (!is.null(diagnostic$config)) {
      lake <- diagnostic$lake
      if (!inherits(lake, "tw_lake") || !DBI::dbIsValid(lake$con)) {
        lake <- tw_connect_lake(diagnostic$config, read_only = TRUE)
        on.exit(tw_close_lake(lake), add = TRUE)
      }
      x <- dplyr::tbl(
        lake$con,
        DBI::Id(
          catalog = "lake",
          schema = diagnostic$schema,
          table = diagnostic$table
        )
      )
    } else {
      x <- diagnostic$data
    }
    if (isTRUE(diagnostic$failed_rows)) {
      return(tibble::as_tibble(tw_collect(
        if (is.finite(limit)) utils::head(x, limit) else x
      )))
    }
  }
  table_result(x, "Diagnostic input")
  if (is.null(rule)) {
    abort(
      "Supply a row formula or select a failed check from tw_quality_report(result)."
    )
  }
  if (inherits(rule, "formula")) {
    check <- rule
  } else {
    scalar(rule, "rule")
    if (!inherits(contract, "tw_contract")) {
      abort("Supply a contract for named checks.")
    }
    if (startsWith(rule, "not_null:")) {
      column <- substring(rule, 10L)
      if (!column %in% union(contract$required, contract$key)) {
        abort("Unknown required-column check.")
      }
      rows <- dplyr::filter(x, is.na(!!rlang::sym(column)))
      return(tibble::as_tibble(tw_collect(
        if (is.finite(limit)) utils::head(rows, limit) else rows
      )))
    }
    if (rule == "unique_key" && length(contract$key)) {
      keys <- dplyr::group_by(x, !!!rlang::syms(contract$key))
      rows <- dplyr::ungroup(dplyr::filter(keys, dplyr::n() > 1L))
      return(tibble::as_tibble(tw_collect(
        if (is.finite(limit)) utils::head(rows, limit) else rows
      )))
    }
    matches <- Filter(
      function(check) identical(check$name, rule),
      contract$rules
    )
    if (length(matches) != 1L) {
      abort("Select one named row rule from tw_quality_report().")
    }
    check <- matches[[1]]$check
  }
  if (!inherits(check, "formula") || length(check) != 2L) {
    abort(
      "This aggregate or custom check does not identify individual rows. Supply an explicit row formula or inspect its specialist diagnostic."
    )
  }
  name <- ".tw_diagnostic_pass"
  while (name %in% names(table_prototype(x))) {
    name <- paste0(name, "_")
  }
  expression <- rlang::as_quosure(check)
  marked <- dplyr::mutate(
    dplyr::ungroup(x),
    !!!stats::setNames(list(expression), name)
  )
  prototype <- table_prototype(marked)[[name]]
  if (!is.logical(prototype) || !is.null(dim(prototype))) {
    abort("Diagnostic formulas must return logical row predicates.")
  }
  rows <- dplyr::filter(
    marked,
    is.na(!!rlang::sym(name)) | !(!!rlang::sym(name))
  )
  rows <- dplyr::select(rows, -dplyr::all_of(name))
  tibble::as_tibble(tw_collect(
    if (is.finite(limit)) utils::head(rows, limit) else rows
  ))
}
