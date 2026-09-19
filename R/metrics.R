#' Define an approved metric
#' @param id,version Identity and version.
#' @param product Input asset id.
#' @param expr Tidy evaluation summary expression, e.g. sum(reserve).
#' @param compute Alternative function(data, dimensions, params) for complex
#'   metrics.
#' @param dimensions Permitted grouping columns.
#' @param time_column Column representing the business date.
#' @param time_behavior `stock` requires exactly one selected date; `flow` may
#'   span dates. Defaults to stock when `time_column` is supplied, otherwise flow.
#' @param input_columns Optional explicit input columns for dynamic expressions
#'   or custom functions. Known expression columns are always checked as well.
#' @param unit Optional unit.
#' @param owner,description Optional business metadata.
#' @param approved Whether business review is complete.
#' @param na_policy Policy description; must be consistent with the expression.
#' @param empty_policy Policy description.
#' @param code_version Version of metric code and dependencies.
#' @return Metric specification. Reports execute it directly without an LLM.
#' @export
#' @examples
#' metric <- dl_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' metric
dl_metric <- function(
  id,
  product,
  expr = NULL,
  compute = NULL,
  dimensions = character(),
  time_column = NULL,
  time_behavior = if (is.null(time_column)) "flow" else "stock",
  unit = "",
  owner = "",
  description = "",
  version = "1.0.0",
  approved = FALSE,
  na_policy = "reject",
  empty_policy = "error",
  code_version,
  input_columns = NULL
) {
  asset_id(id)
  asset_id(product)
  scalar(version, "version")
  scalar(code_version, "code_version")
  for (field in c("unit", "owner", "description")) {
    value <- get(field)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      abort(paste(field, "must be a string; use an empty string to omit it."))
    }
  }
  if (!is.null(input_columns)) {
    invisible(lapply(input_columns, column_name))
  }
  ex <- rlang::enquo(expr)
  if (rlang::quo_is_null(ex) == is.null(compute)) {
    abort("Supply exactly one of expr or compute.")
  }
  if (!is.null(compute) && !is.function(compute)) {
    abort("compute must be a function.")
  }
  time_behavior <- match.arg(time_behavior, c("stock", "flow"))
  if (time_behavior == "stock" && is.null(time_column)) {
    abort("A stock metric requires time_column.")
  }
  if (!is.null(time_column)) {
    column_name(time_column)
  }
  invisible(lapply(dimensions, column_name))
  if (!identical(na_policy, "reject") && !identical(na_policy, "expression")) {
    abort("na_policy is reject or expression.")
  }
  if (!identical(empty_policy, "error")) {
    abort("Empty metric input always produces an error.")
  }
  structure(
    list(
      id = id,
      version = version,
      kind = "metric",
      product = product,
      expr = if (rlang::quo_is_null(ex)) NULL else ex,
      compute = compute,
      dimensions = dimensions,
      time_column = time_column,
      time_behavior = time_behavior,
      unit = unit,
      owner = owner,
      description = description,
      approved = isTRUE(approved),
      na_policy = na_policy,
      empty_policy = empty_policy,
      code_version = code_version,
      input_columns = input_columns
    ),
    class = "dl_metric"
  )
}

#' Calculate a metric on a pinned published release
#' @param lake Connected lake.
#' @param metric Metric definition.
#' @param by Grouping columns.
#' @param at Business date, or a vector for flow metrics.
#' @param release Optional explicit product release id.
#' @param filters Named list of exact-match filters on permitted dimensions.
#' @param params Parameters passed to custom compute functions.
#' @param record Record definition and lineage. Defaults to `TRUE` on a writable
#'   lake and `FALSE` on a read-only lake. Unrecorded results still carry their
#'   complete metric definition and pinned release in the manifest.
#' @return Tibble with a dl_manifest attribute for report reproducibility.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dl_source("orders.file", path, reader = utils::read.csv)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- dl_ingest(lake, source, contract, "orders", code_version = "v1")
#' metric <- dl_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' dl_measure(lake, metric)
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_measure <- function(
  lake,
  metric,
  by = character(),
  at = NULL,
  release = NULL,
  filters = list(),
  params = list(),
  record = !isTRUE(lake$config$read_only)
) {
  assert_lake(lake)
  flag(record, "record")
  if (record) {
    assert_writable(lake)
  }
  if (!inherits(metric, "dl_metric")) {
    abort("metric must be a dl_metric.")
  }
  if (!metric$approved) {
    abort("Metric definition is not approved.")
  }
  if (!all(by %in% metric$dimensions)) {
    abort("Unsupported metric dimensions.")
  }
  if (
    length(filters) &&
      (is.null(names(filters)) || !all(names(filters) %in% metric$dimensions))
  ) {
    abort("Filters must be named permitted dimensions.")
  }
  if (record) {
    dl_register(lake, metric)
  } else {
    old <- query(
      lake,
      paste(
        "SELECT fingerprint FROM",
        meta(lake, "assets"),
        "WHERE id = ? AND version = ? AND kind = 'metric'"
      ),
      list(metric$id, metric$version)
    )
    if (nrow(old) && any(old$fingerprint != fingerprint(metric))) {
      abort(
        "Definition changed without a version bump; legacy formulas require a new metric version."
      )
    }
  }
  ref <- resolve_release(lake, metric$product, release)
  data <- dl_tbl(lake, metric$product, ref$release_id[[1]])
  if (!all(c(by, names(filters), metric$time_column) %in% colnames(data))) {
    abort("Metric columns missing from input product.")
  }
  for (name in names(filters)) {
    data <- dplyr::filter(data, !!rlang::sym(name) %in% !!filters[[name]])
  }
  if (!is.null(at)) {
    if (is.null(metric$time_column)) {
      abort("Metric has no time column.")
    }
    if (anyNA(at) || !length(at)) {
      abort("at cannot be missing or empty.")
    }
    data <- dplyr::filter(data, !!rlang::sym(metric$time_column) %in% !!at)
  }
  if (!count_rows(data)) {
    abort("Metric input is empty.")
  }
  if (metric$time_behavior == "stock") {
    periods <- dplyr::collect(utils::head(
      dplyr::distinct(dplyr::select(data, dplyr::all_of(metric$time_column))),
      2
    ))
    if (nrow(periods) != 1 || anyNA(periods)) {
      abort(
        "Stock metrics require exactly one non-missing business date. Supply at."
      )
    }
  }
  if (metric$na_policy == "reject") {
    columns <- metric_input_columns(metric, colnames(data))
    missing <- null_counts(data, columns)
    if (any(missing > 0)) {
      abort(paste(
        "Missing metric input:",
        paste(names(missing)[missing > 0], collapse = ", ")
      ))
    }
  }

  if (!is.null(metric$compute)) {
    result <- metric$compute(data, by, params)
    if (inherits(result, "tbl_sql")) {
      result <- dplyr::collect(result)
    }
    if (!is.data.frame(result)) {
      abort("Custom metric must return a data.frame or lazy table.")
    }
  } else {
    grouped <- if (length(by)) {
      dplyr::group_by(data, !!!rlang::syms(by))
    } else {
      data
    }
    result <- dplyr::collect(dplyr::summarise(
      grouped,
      value = !!metric$expr,
      .groups = "drop"
    ))
  }
  if (!nrow(result)) {
    abort("Metric returned an empty result.", "dl_metric_empty")
  }
  if (!all(by %in% colnames(result))) {
    abort("Custom metric result must include all requested grouping columns.")
  }
  if (
    (!length(by) && nrow(result) != 1L) ||
      (length(by) && anyDuplicated(as.data.frame(result[by])))
  ) {
    abort("Metric results must contain exactly one row per requested group.")
  }
  # NaN/Inf from zero denominators or overflow is never silently reportable.
  if (
    any(vapply(
      result,
      function(x) is.numeric(x) && any(!is.finite(x)),
      logical(1)
    ))
  ) {
    abort("Metric returned a missing or non-finite numeric result.")
  }
  result <- tibble::as_tibble(result)
  manifest <- list(
    metric = metric$id,
    metric_version = metric$version,
    metric_hash = fingerprint(metric),
    metric_definition = canonical(metric),
    code_version = metric$code_version,
    product = metric$product,
    release_id = ref$release_id[[1]],
    input_quality = ref$quality[[1]],
    published_at = ref$published_at[[1]],
    by = by,
    at = as.character(at),
    filters = filters,
    params = params,
    calculated_at = now(),
    result_hash = fingerprint(result)
  )
  attr(result, "dl_manifest") <- manifest
  if (
    record &&
      !query(
        lake,
        paste(
          "SELECT count(*) AS n FROM",
          meta(lake, "lineage_edges"),
          "WHERE from_id = ? AND from_version = ? AND to_id = ? AND to_version = ? AND relation = 'measured_from'"
        ),
        list(metric$product, ref$release_id[[1]], metric$id, metric$version)
      )$n[[1]]
  ) {
    insert_meta(
      lake,
      "lineage_edges",
      list(
        run_id = "",
        from_id = metric$product,
        from_version = ref$release_id[[1]],
        to_id = metric$id,
        to_version = metric$version,
        relation = "measured_from"
      )
    )
  }
  result
}

#' Freeze metric results and input versions for a report
#' @param lake Connected lake.
#' @param id Immutable report release id.
#' @param results Named list of dl_measure results.
#' @param code_version Reporting code version.
#' @param params Report parameters.
#' @return Report manifest including persisted result values.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dl_source("orders.file", path, reader = utils::read.csv)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- dl_ingest(lake, source, contract, "orders", code_version = "v1")
#' metric <- dl_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' values <- dl_measure(lake, metric)
#' dl_report_release(lake, "report.v1", list(total = values), code_version = "v1")
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_report_release <- function(
  lake,
  id,
  results,
  code_version,
  params = list()
) {
  assert_writable(lake)
  scalar(id, "id")
  scalar(code_version, "code_version")
  if (
    !is.list(results) ||
      !length(results) ||
      is.null(names(results)) ||
      anyNA(names(results)) ||
      any(!nzchar(names(results))) ||
      anyDuplicated(names(results))
  ) {
    abort("results must be a named list.")
  }
  measures <- lapply(results, function(x) {
    m <- attr(x, "dl_manifest")
    if (is.null(m)) {
      abort("Every result must come from dl_measure().")
    }
    if (!identical(m$result_hash, fingerprint(as.data.frame(x)))) {
      # Tibbles and data.frames have the same canonical JSON representation.
      abort("Metric result changed after calculation.")
    }
    list(manifest = m, values = as.data.frame(x))
  })
  manifest <- list(
    id = id,
    code_version = code_version,
    params = params,
    measures = measures
  )
  old <- query(
    lake,
    paste("SELECT manifest FROM", meta(lake, "reports"), "WHERE id=?"),
    list(id)
  )
  if (nrow(old)) {
    if (
      !identical(
        report_identity(old$manifest[[1]]),
        report_identity(jencode(manifest))
      )
    ) {
      abort("Report id already exists with different content.")
    }
    return(dl_report_read(lake, id))
  } else {
    DBI::dbWithTransaction(lake$con, {
      insert_meta(
        lake,
        "reports",
        list(id = id, created_at = now(), manifest = jencode(manifest))
      )
      for (m in measures) {
        insert_meta(
          lake,
          "lineage_edges",
          list(
            run_id = "",
            from_id = m$manifest$metric,
            from_version = m$manifest$metric_version,
            to_id = id,
            to_version = code_version,
            relation = "reported_in"
          )
        )
      }
    })
  }
  manifest
}


metric_input_columns <- function(metric, available) {
  declared <- metric$input_columns
  if (!all(declared %in% available)) {
    abort("Declared metric input columns are missing.")
  }
  if (is.null(metric$expr)) {
    return(declared %||% available)
  }
  expression <- rlang::get_expr(metric$expr)
  found <- intersect(all.vars(expression), available)
  dynamic <- FALSE
  visit <- function(x) {
    if (!is.call(x)) {
      return(invisible(NULL))
    }
    op <- if (is.symbol(x[[1]])) as.character(x[[1]]) else ""
    if (op %in% c("$", "[[") && identical(x[[2]], as.name(".data"))) {
      value <- x[[3]]
      if (op == "$" && is.symbol(value)) {
        value <- as.character(value)
      }
      if (is.character(value) && length(value) == 1L) {
        if (!value %in% available) {
          abort(paste("Metric input column is missing:", value))
        }
        found <<- union(found, value)
      } else {
        dynamic <<- TRUE
      }
    }
    if (op %in% c("get", "mget", "across", "pick", "eval", "eval_tidy")) {
      dynamic <<- TRUE
    }
    invisible(lapply(as.list(x)[-1], visit))
  }
  visit(expression)
  if (dynamic && is.null(declared)) {
    abort(
      "Dynamic metric expressions require input_columns for missing-value checks."
    )
  }
  union(found, declared)
}

report_identity <- function(json) {
  value <- jdecode(json)
  value$measures <- lapply(value$measures, function(x) {
    x$manifest$calculated_at <- NULL
    x
  })
  jencode(value)
}

#' Read an immutable report and its saved results
#'
#' Reads the saved manifest without recalculating any metric. It preserves the
#' original calculation times. Works on read-only lakes, including reports
#' created before version 0.6.0. Values use the JSON representation stored in
#' the report; dates are ISO strings. Use `values_only` for named result tibbles.
#' @param lake Connected lake.
#' @param id Report release ID.
#' @param values_only Return only the named result tables.
#' @returns A manifest list, or a named list of tibbles.
#' @export
#' @examples
#' # After saving report.v1 with dl_report_release():
#' # dl_report_read(lake, "report.v1", values_only = TRUE)
dl_report_read <- function(lake, id, values_only = FALSE) {
  assert_lake(lake)
  scalar(id, "id")
  flag(values_only, "values_only")
  row <- query(
    lake,
    paste("SELECT manifest FROM", meta(lake, "reports"), "WHERE id = ?"),
    list(id)
  )
  if (nrow(row) != 1L) {
    abort(paste("Report not found:", id), "dl_no_report")
  }
  manifest <- jdecode(row$manifest[[1]])
  if (!values_only) {
    return(manifest)
  }
  lapply(manifest$measures, function(x) {
    tibble::as_tibble(lapply(x$values, function(column) {
      if (is.null(column)) {
        return(NA)
      }
      if (is.list(column)) {
        return(unlist(
          lapply(column, function(value) value %||% NA),
          use.names = FALSE
        ))
      }
      column
    }))
  })
}
