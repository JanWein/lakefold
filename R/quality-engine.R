#' Evaluate an interchangeable quality rule
#'
#' Extension packages implement an S3 method for their rule class, inheriting
#' from `dl_rule`. Return the same columns as a native call. Unknown states,
#' empty evidence and malformed results never authorize publication.
#' Rule exceptions are retained locally only when requested by [dl_validate()].
#' @param rule A rule from [dl_rule()], [dl_pointblank()], or an extension.
#' @param data Data frame or lazy table.
#' @param ... Adapter-specific options. Native methods accept `keep_agent`.
#' @returns A quality tibble, with one row per evaluated check.
#' @export
#' @examples
#' dl_run_quality(dl_rule("positive", ~ amount > 0),
#'   data.frame(amount = c(10, -1, NA)))
dl_run_quality <- function(rule, data, ...) UseMethod("dl_run_quality")

#' @export
dl_run_quality.dl_rule <- function(rule, data, ...) {
  # Preserve older serialized pointblank rules without changing their identity.
  if (identical(rule$engine, "pointblank")) {
    return(pointblank_results(rule, data, ...))
  }
  if (!identical(rule$engine, "r")) {
    abort("This quality engine needs a dl_run_quality() method.")
  }
  if (inherits(rule$check, "formula")) {
    if (inherits(data, "tbl_sql")) {
      predicate <- rlang::new_quosure(rule$check[[2]], environment(rule$check))
      units <- dplyr::transmute(data, .dl_pass = !!predicate)
      proto <- dplyr::collect(utils::head(units, 0))
      if (!is.logical(proto$.dl_pass)) {
        abort("Quality formulas must return logical values.")
      }
      counts <- dplyr::collect(dplyr::summarise(
        units,
        failed = sum(as.integer(is.na(.dl_pass) | !.dl_pass), na.rm = TRUE),
        total = dplyr::n()
      ))
      value <- dl_quality_counts(counts$failed %||% 0, counts$total)
    } else {
      value <- rlang::eval_tidy(
        rule$check[[2]],
        data,
        env = environment(rule$check)
      )
      if (!is.logical(value) || !length(value) %in% c(1L, nrow(data))) {
        abort("Quality formulas must return one logical value or one per row.")
      }
      value <- rep(value, length.out = nrow(data))
      value <- dl_quality_counts(sum(is.na(value) | !value), length(value))
    }
  } else {
    value <- rule$check(data)
  }
  if (inherits(value, "dl_quality_counts")) {
    out <- from_counts(
      rule$name,
      value$n_failed,
      value$n_total,
      rule$severity,
      rule$max_failure
    )
  } else if (is.logical(value) && length(value) == 1L && !is.na(value)) {
    out <- from_counts(
      rule$name,
      as.numeric(!value),
      1,
      rule$severity,
      rule$max_failure
    )
  } else {
    out <- quality_row(
      rule$name,
      "error",
      rule$severity,
      message = "Rule must return a non-missing scalar logical or dl_quality_counts()."
    )
  }
  out$engine <- "r"
  out
}

#' @export
dl_run_quality.default <- function(rule, data, ...) {
  abort(
    "Use dl_rule(), dl_pointblank(), or a rule with a dl_run_quality() method."
  )
}

check_quality_output <- function(rows) {
  columns <- names(quality_row("", ""))
  if (!is.data.frame(rows) || !all(columns %in% names(rows)) || !nrow(rows)) {
    abort(
      "A quality adapter must return a non-empty quality tibble with the documented columns."
    )
  }
  if (
    anyNA(rows$status) ||
      !all(
        rows$status %in%
          c("passed", "warning", "failed", "error", "not_checked")
      ) ||
      anyNA(rows$rule) ||
      any(!nzchar(rows$rule)) ||
      anyNA(rows$severity) ||
      !all(rows$severity %in% c("error", "warning"))
  ) {
    abort(
      "The quality adapter returned invalid rule names, states or severities."
    )
  }
  if (!is.numeric(rows$n_failed) || !is.numeric(rows$n_total)) {
    abort("Quality counts must be numeric.")
  }
  evaluated <- rows$status %in% c("passed", "warning", "failed")
  valid <- is.finite(rows$n_failed) &
    is.finite(rows$n_total) &
    rows$n_total > 0 &
    rows$n_failed >= 0 &
    rows$n_failed <= rows$n_total
  if (any(evaluated & !valid)) {
    abort(
      "Evaluated quality rules need valid counts and at least one test unit."
    )
  }
  rows[columns]
}

evaluate_rules <- function(
  rules,
  data,
  keep_agents = FALSE,
  keep_errors = FALSE
) {
  agents <- errors <- list()
  rows <- lapply(rules, function(rule) {
    tryCatch(
      {
        result <- dl_run_quality(rule, data, keep_agent = keep_agents)
        if (keep_agents) {
          agents[[rule$name]] <<- attr(result, "pointblank_agent")
        }
        check_quality_output(result)
      },
      error = function(e) {
        if (keep_errors) {
          errors[[rule$name]] <<- e
        }
        quality_row(
          rule$name,
          "error",
          rule$severity,
          message = "Rule execution failed; no data or raw exception text recorded.",
          engine = rule$engine %||% "custom"
        )
      }
    )
  })
  out <- if (length(rows)) dplyr::bind_rows(rows) else quality_row("", "")[0, ]
  if (keep_agents) {
    attr(out, "pointblank_agents") <- agents
  }
  if (keep_errors) {
    attr(out, "dl_errors") <- errors
  }
  out
}
