#' Define a data contract
#' @param id Optional contract identifier. An unnamed contract is scoped to
#'   the product when added with [add_contract()].
#' @param version Immutable definition version.
#' @param owner Optional business owner.
#' @param description Optional business description.
#' @param grain Optional meaning of one row.
#' @param columns Named character vector of R types: character, integer,
#'   numeric, logical, Date, POSIXct, integer64 or list. A named list of
#'   zero-length prototypes such as `list(id = integer(), amount = double())`
#'   is also accepted. Factors describe character labels: validation preserves
#'   factors in memory, but database storage need not preserve levels or order.
#'   Integer64 columns remain distinct from doubles; no numeric conversion is
#'   performed. Caller-owned DuckDB connections must use
#'   `DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")` to preserve them.
#'   List columns require a target that supports nested data.
#' @param required Non-null columns.
#' @param key Unique key columns.
#' @param rules List of quality rules.
#' @param producer Contact for failed deliveries.
#' @param max_age_hours Maximum release age, or `NULL` to leave freshness
#'   unmonitored.
#' @param allow_empty Whether an empty candidate may be published.
#' @param allow_extra Whether additional columns are permitted.
#' @param operator Optional technical operator, distinct from business owner
#'   and producer.
#' @param column_metadata Optional named lists for declared columns, such as
#'   `list(amount = list(description = "Order value", unit = "EUR"))`.
#' @return A serializable contract specification.
#' @export
#' @examples
#' contract <- contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' contract
contract <- function(
  id = "contract",
  version = "1.0.0",
  owner = "",
  description = "",
  grain = "",
  columns,
  required = names(columns),
  key = character(),
  rules = list(),
  producer = owner,
  max_age_hours = NULL,
  allow_empty = FALSE,
  allow_extra = FALSE,
  operator = NULL,
  column_metadata = list()
) {
  anonymous <- missing(id)
  if (is.list(columns)) {
    if (any(lengths(columns) != 0L)) {
      abort(
        "Prototype columns must be zero-length R vectors, for example integer()."
      )
    }
    columns <- infer_column_types(tibble::as_tibble(
      columns,
      .name_repair = "minimal"
    ))
  }
  asset_id(id)
  scalar(version, "version")
  for (field in c("owner", "description", "grain", "producer")) {
    value <- get(field)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      abort(paste(field, "must be a string; use an empty string to omit it."))
    }
  }
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
  invisible(lapply(names(columns), column_name))
  if (
    !all(
      columns %in%
        c(
          "character",
          "integer",
          "numeric",
          "logical",
          "Date",
          "POSIXct",
          "integer64",
          "list"
        )
    )
  ) {
    abort("Unsupported contract column type.")
  }
  if (!all(c(required, key) %in% names(columns))) {
    abort("required and key must refer to declared columns.")
  }
  if (
    !is.null(max_age_hours) &&
      (!is.numeric(max_age_hours) ||
        length(max_age_hours) != 1 ||
        is.na(max_age_hours) ||
        !is.finite(max_age_hours) ||
        max_age_hours <= 0)
  ) {
    abort("max_age_hours must be positive and finite, or NULL.")
  }
  if (!all(vapply(rules, inherits, logical(1), "tw_rule"))) {
    abort("Use quality_rule() or pointblank_checks() for rules.")
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
    class = "tw_contract"
  )
  if (!is.null(operator)) {
    contract$operator <- operator
  }
  if (length(column_metadata)) {
    contract$column_metadata <- column_metadata
  }
  if (anonymous) {
    attr(contract, "tw_anonymous") <- TRUE
  }
  contract
}

#' Define a quality rule
#' @param name Rule name.
#' @param check Function taking a table and returning a logical vector or
#'   quality_counts(), or a one-sided row predicate such as `~ amount >= 0`.
#'   A scalar function result is one aggregate test; a longer vector must have
#'   one value per row. Formula results are evaluated per row, including scalar
#'   predicates repeated for each row. Missing logical values count as failures.
#'   Lazy formulas run on the backend; arbitrary functions remain responsible
#'   for their own collection.
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
#' rule <- quality_rule("positive", function(data) {
#'   counts <- dplyr::summarise(data, failed = sum(amount <= 0), total = dplyr::n())
#'   if (inherits(counts, "tbl_sql")) counts <- dplyr::collect(counts)
#'   quality_counts(counts$failed, counts$total)
#' })
#' rule$name
quality_rule <- function(
  name,
  check,
  severity = c("error", "warning"),
  max_failure = 0,
  description = ""
) {
  scalar(name, "name")
  if (!is.function(check) && !inherits(check, "formula")) {
    abort("check must be a function or a one-sided formula.")
  }
  if (inherits(check, "formula") && length(check) != 2L) {
    abort("Use a one-sided quality formula, for example ~ amount >= 0.")
  }
  if (
    !is.numeric(max_failure) ||
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
    class = "tw_rule"
  )
}
#' @rdname quality_rule
#' @export
quality_counts <- function(n_failed, n_total) {
  if (
    !is.numeric(n_failed) ||
      !is.numeric(n_total) ||
      length(n_failed) != 1 ||
      length(n_total) != 1 ||
      any(!is.finite(c(n_failed, n_total))) ||
      n_failed != trunc(n_failed) ||
      n_total != trunc(n_total) ||
      n_failed < 0 ||
      n_total < n_failed
  ) {
    abort("Invalid quality counts.")
  }
  structure(
    list(n_failed = n_failed, n_total = n_total),
    class = "tw_quality_counts"
  )
}
#' @rdname quality_rule
#' @export
pointblank_checks <- function(
  name,
  build,
  severity = c("error", "warning"),
  max_failure = 0,
  policy = c("rule", "agent")
) {
  rule <- quality_rule(name, build, severity, max_failure)
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

#' Validate data or check a workflow definition
#'
#' With a table and contract, returns quality evidence. With a composed product
#' or pipeline alone, checks its configuration and returns the definition.
#' Preflight does not evaluate source callbacks or prove data quality.
#' @param data A data frame, lazy table, composed product or pipeline.
#' @param ... Arguments forwarded to a validation method.
#' @param contract Contract definition.
#' @param stage Label stored with each check, such as `"ingest"` or
#'   `"candidate"`.
#' @param keep_agents Retain interrogated pointblank agents as an in-memory
#'   attribute for [pointblank_report()]. Defaults to `FALSE`.
#' @param keep_errors Retain original R conditions in an in-memory `tw_errors`
#'   attribute. They can contain private data and are never persisted in the
#'   registry. Inspect with [quality_errors()]. Defaults to `FALSE`.
#' @return For data, a tibble with one row per check; only passed and warning
#'   permit publication. For a workflow, the validated definition.
#' @export
#' @examples
#' contract <- contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' validate(data.frame(order_id = 1:2, amount = c(25, 75)), contract)
validate <- function(data, contract = NULL, ...) UseMethod("validate")

#' @rdname validate
#' @export
validate.default <- function(
  data,
  contract,
  stage = "candidate",
  keep_agents = FALSE,
  keep_errors = FALSE,
  ...
) {
  rlang::check_dots_empty()
  if (!inherits(contract, "tw_contract")) {
    abort("contract must be a contract.")
  }
  assert_contract_ready(contract)
  scalar(stage, "stage")
  flag(keep_agents, "keep_agents")
  flag(keep_errors, "keep_errors")
  errors <- list()
  result <- list()
  agents <- list()
  add <- function(x) result[[length(result) + 1L]] <<- x
  protect <- function(name, fn) {
    tryCatch(fn(), error = function(e) {
      if (keep_errors) {
        errors[[name]] <<- e
      }
      quality_row(
        name,
        "error",
        message = "Quality evaluation error; inspect rule locally."
      )
    })
  }
  add(protect("schema", function() {
    actual <- names(table_prototype(data))
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
    if (keep_errors) {
      attr(out, "tw_errors") <- errors
    }
    return(out)
  }
  add(protect("types", function() {
    proto <- table_prototype(data)
    good <- vapply(
      names(contract$columns),
      function(n) {
        x <- proto[[n]]
        t <- contract$columns[[n]]
        contract_type_matches(x, t)
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
  required <- union(contract$required, contract$key)
  missing <- tryCatch(null_counts(data, required), error = function(e) e)
  for (column in required) {
    add(protect(paste0("not_null:", column), function() {
      if (inherits(missing, "error")) {
        stop(missing)
      }
      k <- missing[[column]]
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
  rules <- evaluate_rules(contract$rules, data, keep_agents, keep_errors)
  add(rules)
  if (keep_agents) {
    agents <- attr(rules, "pointblank_agents") %||% list()
  }
  if (keep_errors) {
    errors <- c(errors, attr(rules, "tw_errors"))
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
  if (keep_errors) {
    attr(out, "tw_errors") <- errors
  }
  if (keep_agents) {
    attr(out, "pointblank_agents") <- agents
  }
  out
}

quality_ok <- function(results) {
  nrow(results) > 0 && all(results$status %in% c("passed", "warning"))
}


#' Inspect locally retained quality exceptions
#' @param quality Results from `validate(..., keep_errors = TRUE)`.
#' @returns A named list of original R conditions, empty when none were retained.
#' @export
#' @examples
#' contract <- contract("example", columns = c(id = "integer"),
#'   rules = list(quality_rule("broken", function(data) stop("Check configuration"))))
#' quality <- validate(data.frame(id = 1L), contract, keep_errors = TRUE)
#' lapply(quality_errors(quality), conditionMessage)
quality_errors <- function(quality) {
  attr(quality, "tw_errors") %||% list()
}

#' @export
validate.tw_pipeline <- function(data, contract = NULL, ...) {
  rlang::check_dots_empty()
  if (!is.null(contract)) {
    abort("A pipeline already contains its contract.")
  }
  check_pipeline(data)
  need("duckdb")
  check_component(data$steps$land)
  assert_contract_ready(data$steps$validate)
  attr(data, "tw_validated") <- TRUE
  data
}
