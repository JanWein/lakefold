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
#' @param operator Optional technical operator, distinct from business owner
#'   and producer.
#' @param column_metadata Optional named lists for declared columns, such as
#'   `list(amount = list(description = "Order value", unit = "EUR"))`.
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
  allow_extra = FALSE,
  operator = NULL,
  column_metadata = list()
) {
  asset_id(id)
  scalar(version, "version")
  scalar(owner, "owner")
  scalar(grain, "grain")
  flag(allow_empty, "allow_empty")
  flag(allow_extra, "allow_extra")
  if (!is.null(operator)) {
    scalar(operator, "operator")
  }
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
  if (
    length(column_metadata) &&
      (is.null(names(column_metadata)) ||
        anyDuplicated(names(column_metadata)) ||
        !all(names(column_metadata) %in% names(columns)) ||
        !all(vapply(column_metadata, is.list, logical(1))))
  ) {
    abort("column_metadata must be named lists for declared columns.")
  }
  contract <- structure(
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
  if (!is.null(operator)) {
    contract$operator <- operator
  }
  if (length(column_metadata)) {
    contract$column_metadata <- column_metadata
  }
  contract
}

#' Define a quality rule
#' @param name Rule name.
#' @param check Function taking a lazy table and returning a scalar logical or
#'   dl_quality_counts(). No implicit collection of full data is performed.
#' @param severity error blocks publication; warning permits publication.
#' @param max_failure Fraction of permitted failed test units.
#' @param description Rule description.
#' @param build Function creating a pointblank agent from a lazy table.
#' @param policy `"rule"` preserves the explicit `severity` / `max_failure`
#'   gate. `"agent"` uses pointblank's per-step action levels: warnings permit
#'   publication, stop/error and critical states block. Native pointblank
#'   threshold rounding applies. An unconfigured, inactive or errored agent
#'   step always blocks. Old notify-only levels do not authorize publication.
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
  max_failure = 0,
  policy = c("rule", "agent")
) {
  rule <- dl_rule(name, build, severity, max_failure)
  rule$engine <- "pointblank"
  policy <- match.arg(policy)
  if (policy != "rule") {
    rule$policy <- policy
  }
  rule
}

quality_row <- function(
  rule,
  status,
  severity = "error",
  n_failed = NA_real_,
  n_total = NA_real_,
  threshold = 0,
  message = "",
  engine = "contract",
  stage = "candidate",
  segment = "",
  details = ""
) {
  tibble::tibble(
    rule = rule,
    status = status,
    severity = severity,
    n_failed = as.numeric(n_failed),
    n_total = as.numeric(n_total),
    threshold = threshold,
    message = message,
    engine = engine,
    stage = stage,
    segment = segment,
    details = details
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
pointblank_results <- function(rule, data, keep_agent = FALSE) {
  need("pointblank")
  agent <- rule$check(data)
  if (!inherits(agent, "ptblank_agent")) {
    abort("pointblank builder must return an agent.")
  }
  agent <- pointblank::interrogate(
    agent,
    extract_failed = FALSE,
    extract_tbl_checked = FALSE,
    progress = FALSE
  )
  report <- pointblank::get_agent_report(agent, display_table = FALSE)
  if (!nrow(report)) {
    return(quality_row(
      rule$name,
      "not_checked",
      rule$severity,
      message = "Empty pointblank plan.",
      engine = "pointblank"
    ))
  }
  results <- dplyr::bind_rows(lapply(seq_len(nrow(report)), function(i) {
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
    counts <- from_counts(
      name,
      as.numeric(row$units - row$n_pass),
      as.numeric(row$units),
      rule$severity,
      rule$max_failure
    )
    if (identical(rule$policy, "agent")) {
      warn <- if ("W" %in% names(row)) row$W[[1]] else NA
      blocking <- unlist(
        row[intersect(c("S", "E", "C"), names(row))],
        use.names = FALSE
      )
      counts$threshold <- NA_real_
      if (all(is.na(c(warn, blocking)))) {
        counts$status <- "error"
        counts$message <- "Agent policy requires a warning or blocking action level."
      } else if (!counts$status %in% c("error", "not_checked")) {
        counts$status <- if (any(blocking, na.rm = TRUE)) {
          "failed"
        } else if (isTRUE(warn)) {
          "warning"
        } else {
          "passed"
        }
        counts$severity <- if (counts$status == "warning") {
          "warning"
        } else {
          "error"
        }
      }
    }
    counts
  }))
  steps <- agent$validation_set
  if (nrow(steps) != nrow(results)) {
    abort("Unsupported pointblank report layout.")
  }
  for (i in seq_len(nrow(results))) {
    if (
      all(c("seg_col", "seg_val") %in% names(steps)) &&
        length(steps$seg_col[[i]]) &&
        !all(is.na(steps$seg_col[[i]]))
    ) {
      results$segment[[i]] <- jencode(list(
        columns = steps$seg_col[[i]],
        values = steps$seg_val[[i]]
      ))
    }
    actions <- steps$actions[[i]]
    levels <- actions[setdiff(names(actions), "fns")]
    results$details[[i]] <- jencode(list(
      assertion = report$type[[i]],
      columns = report$columns[[i]],
      policy = rule$policy %||% "rule",
      action_levels = levels
    ))
  }
  results$engine <- "pointblank"
  if (keep_agent) {
    attr(results, "pointblank_agent") <- agent
  }
  results
}

#' Validate a candidate against a contract
#' @param data A data frame or lazy table.
#' @param contract Contract definition.
#' @param stage Label stored with each check, such as `"ingest"` or
#'   `"candidate"`.
#' @param keep_agents Retain interrogated pointblank agents as an in-memory
#'   attribute for [dl_pointblank_report()]. Defaults to `FALSE`.
#' @return A tibble with one row per check. Only passed and warning permit
#'   publication.
#' @export
#' @examples
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' dl_validate(data.frame(order_id = 1:2, amount = c(25, 75)), contract)
dl_validate <- function(
  data,
  contract,
  stage = "candidate",
  keep_agents = FALSE
) {
  if (!inherits(contract, "dl_contract")) {
    abort("contract must be a dl_contract.")
  }
  assert_contract_ready(contract)
  scalar(stage, "stage")
  flag(keep_agents, "keep_agents")
  result <- list()
  agents <- list()
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
    out <- dplyr::bind_rows(result)
    out$stage <- stage
    return(out)
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
          rows <- pointblank_results(rule, data, keep_agents)
          if (keep_agents) {
            agents[[rule$name]] <- attr(rows, "pointblank_agent")
          }
          attr(rows, "pointblank_agent") <- NULL
          rows
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
  out <- dplyr::bind_rows(result)
  out$stage <- stage
  out$engine[
    out$engine == "contract" &
      !out$rule %in%
        c(
          "schema",
          "types",
          "nonempty",
          "unique_key",
          paste0("not_null:", union(contract$required, contract$key))
        )
  ] <- "r"
  if (keep_agents) {
    attr(out, "pointblank_agents") <- agents
  }
  out
}

quality_ok <- function(results) {
  nrow(results) > 0 && all(results$status %in% c("passed", "warning"))
}
