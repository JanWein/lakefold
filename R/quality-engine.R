#' Evaluate an interchangeable quality rule
#'
#' Extension packages implement an S3 method for their rule class, inheriting
#' from `tw_rule`. Return the same columns as a native call. Unknown states,
#' empty evidence and malformed results never authorize publication.
#' Rule exceptions are retained locally only when requested by [validate()].
#' @param rule A rule from [quality_rule()], [pointblank_checks()], or an extension.
#' @param data Data frame or lazy table.
#' @param ... Adapter-specific options. Native methods accept `keep_agent`.
#' @returns A quality tibble, with one row per evaluated check.
#' @export
#' @examples
#' run_quality(quality_rule("positive", ~ amount > 0),
#'   data.frame(amount = c(10, -1, NA)))
run_quality <- function(rule, data, ...) UseMethod("run_quality")

normalize_quality_engine <- function(engine) {
  engine <- match.arg(engine, c("native", "pointblank"))
  if (engine == "native") "r" else engine
}

quality_formula_units <- function(data, predicate) {
  if (!inherits(predicate, "formula") || length(predicate) != 2L) {
    abort("Use a one-sided quality formula, for example ~ amount >= 0.")
  }
  if (is_lazy_table(data)) {
    expression <- rlang::as_quosure(predicate)
    units <- dplyr::transmute(dplyr::ungroup(data), .tw_pass = !!expression)
    value <- table_prototype(units)$.tw_pass
  } else {
    value <- rlang::eval_tidy(
      predicate[[2]],
      data,
      env = environment(predicate)
    )
    if (!length(value) %in% c(1L, nrow(data))) {
      abort("Quality formulas must return one logical value or one per row.")
    }
    units <- NULL
  }
  if (!is.logical(value) || !is.null(dim(value))) {
    abort("Quality formulas must return one logical value or one per row.")
  }
  if (is.null(units)) {
    units <- tibble::tibble(.tw_pass = rep(value, length.out = nrow(data)))
  }
  units
}

#' @export
run_quality.tw_rule <- function(rule, data, ...) {
  if (identical(rule$engine, "pointblank")) {
    return(pointblank_results(rule, data, ...))
  }
  if (!identical(rule$engine, "r")) {
    abort("This quality engine needs a run_quality() method.")
  }
  if (inherits(rule$check, "formula")) {
    units <- quality_formula_units(data, rule$check)
    if (is_lazy_table(units)) {
      .tw_pass <- NULL
      counts <- dplyr::collect(dplyr::summarise(
        units,
        failed = sum(as.integer(is.na(.tw_pass) | !.tw_pass), na.rm = TRUE),
        total = dplyr::n()
      ))
      value <- quality_counts(
        if (is.na(counts$failed)) 0 else counts$failed,
        counts$total
      )
    } else {
      value <- units$.tw_pass
      value <- quality_counts(sum(is.na(value) | !value), length(value))
    }
  } else {
    value <- rule$check(data)
    if (is.logical(value) && is.null(dim(value))) {
      if (length(value) != 1L && length(value) != count_rows(data)) {
        abort(
          "A quality function must return one logical value, one per row, or quality_counts()."
        )
      }
      value <- quality_counts(sum(is.na(value) | !value), length(value))
    }
  }
  if (inherits(value, "tw_quality_counts")) {
    out <- from_counts(
      rule$name,
      value$n_failed,
      value$n_total,
      rule$severity,
      rule$max_failure
    )
  } else {
    abort(
      "A quality function must return logical values or quality_counts(); numeric scores are not pass/fail results."
    )
  }
  out$engine <- "r"
  out
}

#' @export
run_quality.default <- function(rule, data, ...) {
  abort(
    "Use quality_rule(), pointblank_checks(), or a rule with a run_quality() method."
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
        result <- run_quality(rule, data, keep_agent = keep_agents)
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
    attr(out, "tw_errors") <- errors
  }
  out
}
