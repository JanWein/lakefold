#' Define a data contract
#' @param id Unique asset identifier.
#' @param version Immutable definition version.
#' @param owner Business owner.
#' @param description Business description.
#' @param grain Meaning of one row.
#' @param columns Named character vector of R types: character, integer,
#'   numeric,
#'   logical, Date, POSIXct.
#' @param required Non-null columns.
#' @param key Unique key columns.
#' @param rules List of quality rules.
#' @param producer Contact for failed deliveries.
#' @param max_age_hours Maximum release age.
#' @param allow_empty Whether an empty candidate may be published.
#' @param allow_extra Whether additional columns are permitted.
#' @return A serializable contract specification.
#' @export
#' @examples
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' contract
dl_contract <- function(
  id,
  version,
  owner,
  description,
  grain,
  columns,
  required = names(columns),
  key = character(),
  rules = list(),
  producer = owner,
  max_age_hours = 48,
  allow_empty = FALSE,
  allow_extra = FALSE
) {
  asset_id(id)
  scalar(version, "version")
  scalar(owner, "owner")
  scalar(grain, "grain")
  if (
    is.null(names(columns)) || anyDuplicated(names(columns)) || !length(columns)
  ) {
    abort("columns must be a named type vector.")
  }
  invisible(lapply(names(columns), ident))
  if (
    !all(
      columns %in%
        c("character", "integer", "numeric", "logical", "Date", "POSIXct")
    )
  ) {
    abort("Unsupported contract column type.")
  }
  if (!all(c(required, key) %in% names(columns))) {
    abort("required and key must refer to declared columns.")
  }
  if (
    !is.numeric(max_age_hours) ||
      length(max_age_hours) != 1 ||
      is.na(max_age_hours) ||
      max_age_hours <= 0
  ) {
    abort("max_age_hours must be positive.")
  }
  if (!all(vapply(rules, inherits, logical(1), "dl_rule"))) {
    abort("Use dl_rule() or dl_pointblank() for rules.")
  }
  if (anyDuplicated(vapply(rules, `[[`, character(1), "name"))) {
    abort("Rule names must be unique.")
  }
  structure(
    list(
      id = id,
      version = version,
      kind = "contract",
      owner = owner,
      description = description,
      grain = grain,
      columns = as.list(columns),
      required = required,
      key = key,
      rules = rules,
      producer = producer,
      max_age_hours = max_age_hours,
      allow_empty = allow_empty,
      allow_extra = allow_extra
    ),
    class = "dl_contract"
  )
}

#' Define a quality rule
#' @param name Rule name.
#' @param check Function taking a lazy table and returning a scalar logical or
#'   dl_quality_counts(). No implicit collection of full data is performed.
#' @param severity error blocks publication; warning permits publication.
#' @param max_failure Fraction of permitted failed test units.
#' @param description Rule description.
#' @param build Function creating a pointblank agent from a lazy table.
#' @param n_failed,n_total Failed and total test units.
#' @return A rule specification or counts object.
#' @export
#' @examples
#' rule <- dl_rule("positive", function(data) {
#'   counts <- dplyr::summarise(data, failed = sum(amount <= 0), total = dplyr::n())
#'   if (inherits(counts, "tbl_sql")) counts <- dplyr::collect(counts)
#'   dl_quality_counts(counts$failed, counts$total)
#' })
#' rule$name
dl_rule <- function(
  name,
  check,
  severity = c("error", "warning"),
  max_failure = 0,
  description = ""
) {
  scalar(name, "name")
  if (!is.function(check)) {
    abort("check must be a function.")
  }
  if (
    length(max_failure) != 1 ||
      !is.finite(max_failure) ||
      max_failure < 0 ||
      max_failure > 1
  ) {
    abort("max_failure must be between 0 and 1.")
  }
  structure(
    list(
      name = name,
      check = check,
      severity = match.arg(severity),
      max_failure = max_failure,
      description = description,
      engine = "r"
    ),
    class = "dl_rule"
  )
}
#' @rdname dl_rule
#' @export
dl_quality_counts <- function(n_failed, n_total) {
  if (
    length(n_failed) != 1 ||
      length(n_total) != 1 ||
      any(!is.finite(c(n_failed, n_total))) ||
      n_failed < 0 ||
      n_total < n_failed
  ) {
    abort("Invalid quality counts.")
  }
  structure(
    list(n_failed = n_failed, n_total = n_total),
    class = "dl_quality_counts"
  )
}
#' @rdname dl_rule
#' @export
dl_pointblank <- function(
  name,
  build,
  severity = c("error", "warning"),
  max_failure = 0
) {
  rule <- dl_rule(name, build, severity, max_failure)
  rule$engine <- "pointblank"
  rule
}

quality_row <- function(
  rule,
  status,
  severity = "error",
  n_failed = NA_real_,
  n_total = NA_real_,
  threshold = 0,
  message = ""
) {
  tibble::tibble(
    rule = rule,
    status = status,
    severity = severity,
    n_failed = as.numeric(n_failed),
    n_total = as.numeric(n_total),
    threshold = threshold,
    message = message
  )
}
from_counts <- function(
  name,
  failed,
  total,
  severity = "error",
  threshold = 0
) {
  if (!is.finite(total) || total <= 0) {
    return(quality_row(
      name,
      "not_checked",
      severity,
      failed,
      total,
      threshold,
      "No test units."
    ))
  }
  status <- if (failed / total <= threshold) {
    "passed"
  } else if (severity == "warning") {
    "warning"
  } else {
    "failed"
  }
  quality_row(name, status, severity, failed, total, threshold)
}
pointblank_results <- function(rule, data) {
  need("pointblank")
  agent <- rule$check(data)
  if (!inherits(agent, "ptblank_agent")) {
    abort("pointblank builder must return an agent.")
  }
  agent <- pointblank::interrogate(agent, extract_failed = FALSE)
  report <- pointblank::get_agent_report(agent, display_table = FALSE)
  if (!nrow(report)) {
    return(quality_row(
      rule$name,
      "not_checked",
      rule$severity,
      message = "Empty pointblank plan."
    ))
  }
  dplyr::bind_rows(lapply(seq_len(nrow(report)), function(i) {
    row <- report[i, ]
    name <- paste(rule$name, row$i, sep = ":")
    if (!isTRUE(row$active[[1]])) {
      return(quality_row(
        name,
        "not_checked",
        rule$severity,
        message = "Inactive pointblank step."
      ))
    }
    if (!identical(as.character(row$eval[[1]]), "OK")) {
      return(quality_row(
        name,
        "error",
        rule$severity,
        message = "pointblank evaluation did not complete cleanly."
      ))
    }
    from_counts(
      name,
      as.numeric(row$units - row$n_pass),
      as.numeric(row$units),
      rule$severity,
      rule$max_failure
    )
  }))
}

#' Validate a candidate against a contract
#' @param data A data frame or lazy table.
#' @param contract Contract definition.
#' @return A tibble with one row per check. Only passed and warning permit
#'   publication.
#' @export
#' @examples
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' dl_validate(data.frame(order_id = 1:2, amount = c(25, 75)), contract)
dl_validate <- function(data, contract) {
  if (!inherits(contract, "dl_contract")) {
    abort("contract must be a dl_contract.")
  }
  result <- list()
  add <- function(x) result[[length(result) + 1L]] <<- x
  protect <- function(name, fn) {
    tryCatch(fn(), error = function(e) {
      quality_row(
        name,
        "error",
        message = "Quality evaluation error; inspect rule locally."
      )
    })
  }
  add(protect("schema", function() {
    actual <- colnames(data)
    expected <- names(contract$columns)
    good <- all(expected %in% actual) &&
      (contract$allow_extra || setequal(actual, expected))
    quality_row(
      "schema",
      if (good) "passed" else "failed",
      n_failed = as.numeric(!good),
      n_total = 1,
      message = if (good) {
        ""
      } else {
        paste("Expected columns:", paste(expected, collapse = ", "))
      }
    )
  }))
  if (!identical(result[[1]]$status[[1]], "passed")) {
    return(dplyr::bind_rows(result))
  }
  add(protect("types", function() {
    proto <- if (inherits(data, "tbl_sql")) {
      dplyr::collect(utils::head(data, 0))
    } else {
      data[0, , drop = FALSE]
    }
    good <- vapply(
      names(contract$columns),
      function(n) {
        x <- proto[[n]]
        t <- contract$columns[[n]]
        switch(
          t,
          numeric = is.numeric(x) &&
            !inherits(x, c("Date", "POSIXt", "integer64")),
          integer = is.integer(x),
          character = is.character(x),
          logical = is.logical(x),
          Date = inherits(x, "Date"),
          POSIXct = inherits(x, "POSIXct")
        )
      },
      logical(1)
    )
    quality_row(
      "types",
      if (all(good)) "passed" else "failed",
      n_failed = sum(!good),
      n_total = length(good),
      message = paste(names(good)[!good], collapse = ", ")
    )
  }))
  n <- tryCatch(count_rows(data), error = function(e) NA_real_)
  add(quality_row(
    "nonempty",
    if (is.na(n)) {
      "error"
    } else if (n > 0 || contract$allow_empty) {
      "passed"
    } else {
      "failed"
    },
    n_failed = as.numeric(is.na(n) || (n == 0 && !contract$allow_empty)),
    n_total = 1
  ))
  for (column in union(contract$required, contract$key)) {
    add(protect(paste0("not_null:", column), function() {
      k <- count_rows(dplyr::filter(data, is.na(!!rlang::sym(column))))
      quality_row(
        paste0("not_null:", column),
        if (k == 0) "passed" else "failed",
        n_failed = k,
        n_total = n
      )
    }))
  }
  if (length(contract$key)) {
    add(protect("unique_key", function() {
      distinct <- count_rows(dplyr::distinct(
        data,
        !!!rlang::syms(contract$key)
      ))
      quality_row(
        "unique_key",
        if (n == distinct) "passed" else "failed",
        n_failed = n - distinct,
        n_total = n
      )
    }))
  }
  for (rule in contract$rules) {
    add(tryCatch(
      {
        if (rule$engine == "pointblank") {
          pointblank_results(rule, data)
        } else {
          value <- rule$check(data)
          if (inherits(value, "dl_quality_counts")) {
            from_counts(
              rule$name,
              value$n_failed,
              value$n_total,
              rule$severity,
              rule$max_failure
            )
          } else if (
            is.logical(value) && length(value) == 1L && !is.na(value)
          ) {
            from_counts(
              rule$name,
              as.numeric(!value),
              1,
              rule$severity,
              rule$max_failure
            )
          } else {
            quality_row(
              rule$name,
              "error",
              rule$severity,
              message = "Rule must return a non-missing scalar logical or dl_quality_counts()."
            )
          }
        }
      },
      error = function(e) {
        quality_row(
          rule$name,
          "error",
          rule$severity,
          message = "Rule execution failed; no data or raw exception text recorded."
        )
      }
    ))
  }
  dplyr::bind_rows(result)
}

quality_ok <- function(results) {
  nrow(results) > 0 && all(results$status %in% c("passed", "warning"))
}
