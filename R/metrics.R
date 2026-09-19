#' Define an approved metric
#' @param id,version Identity and version.
#' @param product Input asset id.
#' @param expr Tidy evaluation summary expression, e.g. sum(reserve).
#' @param compute Alternative function(data, dimensions, params) for complex
#'   metrics.
#' @param dimensions Permitted grouping columns.
#' @param time_column Column representing the business date.
#' @param time_behavior stock requires exactly one selected date; flow may span
#'   dates.
#' @param unit Unit.
#' @param owner,description Business metadata.
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
  time_behavior = c("stock", "flow"),
  unit,
  owner,
  description,
  version = "1.0.0",
  approved = FALSE,
  na_policy = "reject",
  empty_policy = "error",
  code_version
) {
  asset_id(id)
  asset_id(product)
  scalar(version, "version")
  scalar(code_version, "code_version")
  scalar(unit, "unit")
  scalar(owner, "owner")
  scalar(description, "description")
  ex <- rlang::enquo(expr)
  if (rlang::quo_is_null(ex) == is.null(compute)) {
    abort("Supply exactly one of expr or compute.")
  }
  if (!is.null(compute) && !is.function(compute)) {
    abort("compute must be a function.")
  }
  time_behavior <- match.arg(time_behavior)
  if (time_behavior == "stock" && is.null(time_column)) {
    abort("A stock metric requires time_column.")
  }
  if (!is.null(time_column)) {
    ident(time_column)
  }
  invisible(lapply(dimensions, ident))
  if (!identical(na_policy, "reject") && !identical(na_policy, "expression")) {
    abort("na_policy is reject or expression.")
  }
  if (!identical(empty_policy, "error")) {
    abort("Only explicit error on empty input is supported in v0.1.")
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
      code_version = code_version
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
  params = list()
) {
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
  dl_register(lake, metric)
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
    columns <- if (!is.null(metric$expr)) {
      intersect(all.vars(rlang::get_expr(metric$expr)), colnames(data))
    } else {
      colnames(data)
    }
    for (column in columns) {
      if (count_rows(dplyr::filter(data, is.na(!!rlang::sym(column)))) > 0) {
        abort(paste("Missing metric input:", column))
      }
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
  scalar(id, "id")
  scalar(code_version, "code_version")
  if (
    !length(results) || is.null(names(results)) || anyDuplicated(names(results))
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
    if (!identical(old$manifest[[1]], jencode(manifest))) {
      abort("Report id already exists with different content.")
    }
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
