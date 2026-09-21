#' Define a metric for exploration or approved reporting
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
#' @param code_version Version of metric code and dependencies. Required for
#'   approved definitions; exploratory definitions may omit it.
#' @return Metric specification. Reports execute it directly without an LLM.
#' @export
#' @examples
#' metric <- dr_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' metric
dr_metric <- function(
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
  code_version = NULL,
  input_columns = NULL
) {
  dataraft.core::asset_id(id)
  dataraft.core::asset_id(product)
  dataraft.core::scalar(version, "version")
  dataraft.core::flag(approved, "approved")
  if (approved || !is.null(code_version)) {
    dataraft.core::scalar(code_version, "code_version")
    if (!nzchar(trimws(code_version))) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "code_version must not be blank."
      )
    }
  }
  for (field in c("unit", "owner", "description")) {
    value <- get(field)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        paste(field, "must be a string; use an empty string to omit it.")
      )
    }
  }
  if (!is.null(input_columns)) {
    invisible(lapply(input_columns, dataraft.core::column_name))
  }
  ex <- rlang::enquo(expr)
  if (rlang::quo_is_null(ex) == is.null(compute)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Supply exactly one of expr or compute."
    )
  }
  if (!is.null(compute) && !is.function(compute)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "compute must be a function."
    )
  }
  time_behavior <- match.arg(time_behavior, c("stock", "flow"))
  if (time_behavior == "stock" && is.null(time_column)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "A stock metric requires time_column."
    )
  }
  if (!is.null(time_column)) {
    dataraft.core::column_name(time_column)
  }
  invisible(lapply(dimensions, dataraft.core::column_name))
  if (!identical(na_policy, "reject") && !identical(na_policy, "expression")) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "na_policy is reject or expression."
    )
  }
  if (!identical(empty_policy, "error")) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Empty metric input always produces an error."
    )
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
    class = "dr_metric"
  )
}


#' Calculate a metric on a pinned published release
#'
#' A successful publication result supplies its exact asset and release. Later
#' publications do not change that input. Result-based measurement does not
#' register definitions or write lineage; its manifest still contains all
#' metric and input evidence needed by [dr_report_release()]. A live caller-owned
#' lake is borrowed when available. Otherwise the saved configuration opens an
#' owned read-only connection that closes before returning, including on errors.
#' @param x Connected lake or successful `dr_run_result`. In-memory [dataraft.core::dr_trial()]
#'   results support exploratory measurements with the same definitions. They
#'   cannot be recorded or saved in issued reports, even for approved metrics.
#' @param metric Single metric definition.
#' @param metrics Nonempty list of metric definitions for a measurement set.
#'   Optional unique names label metrics in the collected table. Supply either
#'   `metric` or `metrics`.
#' @param period For `metrics`, `"each"` calculates each selected date separately;
#'   `"aggregate"` calculates across selected dates. Stock metrics still require
#'   one date. With `at = NULL`, dates are not split automatically.
#' @param by Grouping columns selected from the metric's permitted dimensions.
#'   Omitting `by` calculates an overall total, with a reminder when dimensions
#'   are available. Use `by = character()` to request an overall total explicitly.
#' @param at Business date, or a vector for flow metrics.
#' @param release Optional explicit product release id for a connected lake.
#'   For a publication result it must be omitted or match that exact release.
#' @param filters Named list of exact-match filters on permitted dimensions.
#' @param params Parameters passed to custom compute functions.
#' @param record Record definition and lineage. Defaults to `TRUE` on a writable
#'   lake and `FALSE` on a read-only lake or publication result. Use a connected
#'   writable lake for `record = TRUE`. Unrecorded results still carry their
#'   complete metric definition and pinned release in the manifest. Exploratory
#'   metrics always default to `record = FALSE` and cannot be saved in reports.
#' @return For `metric`, a tibble with a dr_manifest attribute. For `metrics`,
#'   a `dr_measurement_set` retaining each original result and manifest.
#'   `dataraft.core::dr_collect()` returns an ordinary long tibble with grouping columns,
#'   `.metric`, `.period` (a list column of selected dates), `.unit` and `value`.
#'   Grouped results are ordered by the requested dimensions using C collation
#'   so database row order does not change report identity.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("dataraft-example-")
#' config <- dataraft.lake::dr_lake_config(
#'   dataraft.lake::dr_registry_duckdb(file.path(root, "lake.db")),
#'   dataraft.lake::dr_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dataraft.lake::dr_connect_lake(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dataraft.core::dr_source_file("orders.file", path, reader = utils::read.csv)
#' contract <- dataraft.core::dr_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- dataraft.core::dr_product("orders", contract = contract, code_version = "v1") |>
#'   dataraft.core::dr_add_source(source) |> dataraft.core::dr_publish(to = lake)
#' metric <- dr_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' release |> dr_measure(metric)
#' dataraft.lake::dr_disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
dr_measure <- function(
  x,
  metric = NULL,
  by = character(),
  at = NULL,
  release = NULL,
  filters = list(),
  params = list(),
  record = NULL,
  metrics = NULL,
  period = c("each", "aggregate")
) {
  if (inherits(x, "dr_model_result")) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Choose a reporting table with dr_product('report', model_result, table = 'table_name'), then dr_trial() or dr_publish() that product before dr_measure()."
    )
  }
  if (!is.null(metrics)) {
    if (!is.null(metric)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Supply either metric or metrics, not both."
      )
    }
    result <- measure_set(
      x,
      metrics,
      by,
      at,
      release,
      filters,
      params,
      record,
      match.arg(period)
    )
    if (missing(by)) {
      inform_measure_grouping(metrics)
    }
    return(result)
  }
  if (!missing(period)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "period applies only when using metrics."
    )
  }
  if (!inherits(metric, "dr_metric")) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "metric must be a metric."
    )
  }
  if (!isTRUE(metric$approved)) {
    record <- record %||% FALSE
    dataraft.core::flag(record, "record")
    if (record) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Exploratory metrics cannot be recorded. Use record = FALSE."
      )
    }
  }
  exploring <- inherits(x, "dr_run_result") && identical(x$status, "completed")
  if (exploring) {
    record <- record %||% FALSE
    dataraft.core::flag(record, "record")
    if (record || !is.null(release)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Trial measurements cannot record lineage or select a release. Publish the product first."
      )
    }
    if (!identical(metric$product, x$asset)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "The metric input asset does not match this trial result."
      )
    }
    data <- x$data
    dataraft.core::table_result(data, "Trial measurement input")
    lake <- source <- NULL
    ref <- data.frame(
      release_id = NA_character_,
      quality = "trial",
      published_at = NA_character_
    )
  } else if (inherits(x, "dr_run_result")) {
    if (
      !is.character(x$status) ||
        length(x$status) != 1L ||
        is.na(x$status) ||
        !x$status %in% c("published", "cached") ||
        !is.character(x$asset) ||
        length(x$asset) != 1L ||
        is.na(x$asset) ||
        !nzchar(x$asset) ||
        !is.character(x$release_id) ||
        length(x$release_id) != 1L ||
        is.na(x$release_id) ||
        !nzchar(x$release_id)
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "dr_measure() needs a successful published result with an exact release."
      )
    }
    if (!identical(metric$product, x$asset)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "The metric input asset does not match this publication result."
      )
    }
    if (!is.null(release) && !identical(release, x$release_id)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "A publication result is pinned. Omit release or use its exact release id."
      )
    }
    record <- record %||% FALSE
    dataraft.core::flag(record, "record")
    if (record) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Use a connected writable lake to record metric definitions and lineage."
      )
    }
    source <- dataraft.core::normalize_result_source(x)
    if (!inherits(source, "dr_release_source")) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "The publication result has no readable lake release reference."
      )
    }
    borrowed <- inherits(x$output_lake, "dr_lake") &&
      DBI::dbIsValid(x$output_lake$con)
    if (borrowed) {
      lake <- x$output_lake
      if (
        inherits(source$lake, "dr_config") &&
          !identical(
            source$lake[c("backend", "catalog", "storage")],
            lake$config[c("backend", "catalog", "storage")]
          )
      ) {
        dataraft.core::abort(
          subclass = "dataraft_error_metrics",
          "The result's connection and saved configuration describe different lakes."
        )
      }
    } else if (inherits(source$lake, "dr_config")) {
      lake <- dataraft.lake::dr_connect_lake(source$lake, read_only = TRUE)
      on.exit(dataraft.lake::dr_disconnect_lake(lake), add = TRUE)
    } else {
      lake <- source$lake
      dataraft.lake::assert_lake(lake)
    }
    release <- x$release_id
  } else {
    lake <- x
    dataraft.lake::assert_lake(lake)
    record <- record %||% !isTRUE(lake$config$read_only)
    dataraft.core::flag(record, "record")
    if (record) dataraft.lake::assert_writable(lake)
  }
  if (!all(by %in% metric$dimensions)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Unsupported metric dimensions."
    )
  }
  if (
    length(filters) &&
      (is.null(names(filters)) || !all(names(filters) %in% metric$dimensions))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Filters must be named permitted dimensions."
    )
  }
  if (record) {
    dataraft.lake::dr_register(lake, metric)
  } else if (!exploring && isTRUE(metric$approved)) {
    old <- dataraft.lake::query(
      lake,
      paste(
        "SELECT fingerprint FROM",
        dataraft.lake::meta(lake, "assets"),
        "WHERE id = ? AND version = ? AND kind = 'metric'"
      ),
      list(metric$id, metric$version)
    )
    if (
      nrow(old) && any(old$fingerprint != dataraft.core::fingerprint(metric))
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Definition changed without a version bump."
      )
    }
  }
  if (!exploring) {
    ref <- dataraft.lake::resolve_release(lake, metric$product, release)
    data <- dataraft.lake::dr_tbl(lake, metric$product, ref$release_id[[1]])
  }
  if (!all(c(by, names(filters), metric$time_column) %in% colnames(data))) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric columns missing from input product."
    )
  }
  for (name in names(filters)) {
    data <- dplyr::filter(data, !!rlang::sym(name) %in% !!filters[[name]])
  }
  if (!is.null(at)) {
    if (is.null(metric$time_column)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Metric has no time column."
      )
    }
    if (anyNA(at) || !length(at)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "at cannot be missing or empty."
      )
    }
    data <- dplyr::filter(data, !!rlang::sym(metric$time_column) %in% !!at)
  }
  if (!dataraft.core::count_rows(data)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric input is empty."
    )
  }
  if (metric$time_behavior == "stock") {
    periods <- dplyr::collect(utils::head(
      dplyr::distinct(dplyr::select(data, dplyr::all_of(metric$time_column))),
      2
    ))
    if (nrow(periods) != 1 || anyNA(periods)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Stock metrics require exactly one non-missing business date. Supply at."
      )
    }
  }
  if (metric$na_policy == "reject") {
    columns <- metric_input_columns(metric, colnames(data))
    missing <- dataraft.core::null_counts(data, columns)
    if (any(missing > 0)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        paste(
          "Missing metric input:",
          paste(names(missing)[missing > 0], collapse = ", ")
        )
      )
    }
  }

  if (!is.null(metric$compute)) {
    result <- metric$compute(data, by, params)
    if (inherits(result, "tbl_sql")) {
      result <- dplyr::collect(result)
    }
    if (!is.data.frame(result)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Custom metric must return a data.frame or lazy table."
      )
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
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric returned an empty result.",
      "dr_metric_empty"
    )
  }
  if (!all(by %in% colnames(result))) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Custom metric result must include all requested grouping columns."
    )
  }
  if (
    (!length(by) && nrow(result) != 1L) ||
      (length(by) && anyDuplicated(as.data.frame(result[by])))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric results must contain exactly one row per requested group."
    )
  }
  # NaN/Inf from zero denominators or overflow is never silently reportable.
  if (
    any(vapply(
      result,
      function(x) is.numeric(x) && any(!is.finite(x)),
      logical(1)
    ))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric returned a missing or non-finite numeric result."
    )
  }
  result <- tibble::as_tibble(result)
  if (length(by)) {
    result <- dplyr::arrange(result, !!!rlang::syms(by), .locale = "C")
  }
  manifest <- list(
    metric = metric$id,
    metric_version = metric$version,
    metric_hash = dataraft.core::fingerprint(metric),
    metric_definition = dataraft.core::canonical(metric),
    code_version = metric$code_version,
    product = metric$product,
    release_id = ref$release_id[[1]],
    input_published = !exploring,
    input_run = if (exploring) x$run_id else NULL,
    input_quality = ref$quality[[1]],
    published_at = ref$published_at[[1]],
    by = by,
    at = as.character(at),
    filters = filters,
    params = params,
    calculated_at = dataraft.core::now(),
    result_hash = dataraft.core::report_fingerprint(result)
  )
  attr(result, "dr_manifest") <- manifest
  attr(result, "dr_quality_reference") <- if (exploring) {
    list(
      trial_quality = dataraft.core::dr_quality(x),
      asset = x$asset,
      run_id = x$run_id
    )
  } else {
    list(
      config = if (
        inherits(x, "dr_run_result") && inherits(source$lake, "dr_config")
      ) {
        source$lake
      } else {
        lake$config
      },
      lake = lake,
      asset = metric$product,
      release = ref$release_id[[1]]
    )
  }
  if (
    record &&
      !dataraft.lake::query(
        lake,
        paste(
          "SELECT count(*) AS n FROM",
          dataraft.lake::meta(lake, "lineage_edges"),
          "WHERE from_id = ? AND from_version = ? AND to_id = ? AND to_version = ? AND relation = 'measured_from'"
        ),
        list(metric$product, ref$release_id[[1]], metric$id, metric$version)
      )$n[[1]]
  ) {
    dataraft.lake::insert_meta(
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
  if (missing(by)) {
    inform_measure_grouping(list(metric))
  }
  result
}


inform_measure_grouping <- function(metrics) {
  rlang::local_error_call(rlang::caller_env())
  dimensions <- Reduce(intersect, lapply(metrics, `[[`, "dimensions"))
  if (length(dimensions)) {
    message(
      "Calculated an overall total. For grouped values use by = c(",
      paste(encodeString(dimensions, quote = '"'), collapse = ", "),
      "). Use by = character() for an explicit overall total."
    )
  }
}


#' Freeze metric results and input versions for a report
#'
#' Reports preserve double precision. Nested list columns are rejected before
#' writing; expand them into named atomic columns in the metric calculation.
#' Report JSON stores numeric values. Integer64 columns must stay within
#' -2^53 to 2^53 inclusive so saved values can be read back exactly. Larger
#' integers are rejected before writing; retain those individual results
#' in a storage format with integer64 support.
#' @param lake For data-first use, the measurement results. Also accepts a
#'   connected lake, lake configuration or local lake folder for lake-first use.
#' @param to Report destination. When omitted in data-first use, inferred from
#'   matching saved lake references on every result.
#'   Supplied connections remain open; internally opened connections always close.
#' @param id Immutable report release id.
#' @param results Named list of measure results, or a measurement set.
#' @param code_version Reporting code version.
#' @param params Report parameters.
#' @return Report manifest including result values as data frames, both on
#'   initial save and an identical retry. Retries preserve original timestamps.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("dataraft-example-")
#' config <- dataraft.lake::dr_lake_config(
#'   dataraft.lake::dr_registry_duckdb(file.path(root, "lake.db")),
#'   dataraft.lake::dr_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dataraft.lake::dr_connect_lake(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dataraft.core::dr_source_file("orders.file", path, reader = utils::read.csv)
#' contract <- dataraft.core::dr_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- dataraft.core::dr_product("orders", contract = contract, code_version = "v1") |>
#'   dataraft.core::dr_add_source(source) |> dataraft.core::dr_publish(to = lake)
#' metric <- dr_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' values <- dr_measure(lake, metric)
#' dr_report_release(lake, "report.v1", list(total = values), code_version = "v1")
#' dataraft.lake::dr_disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
dr_report_release <- function(
  lake = NULL,
  id,
  results = NULL,
  code_version,
  params = list(),
  to = NULL
) {
  if (
    inherits(lake, "dr_measurement_set") ||
      is.data.frame(lake) ||
      (is.list(lake) && !inherits(lake, c("dr_lake", "dr_config")))
  ) {
    if (!is.null(results)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Supply results only once."
      )
    }
    results <- lake
    lake <- NULL
  }
  if (!is.null(to)) {
    if (!is.null(lake)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Supply either lake or to, not both."
      )
    }
    lake <- to
  }
  if (is.data.frame(results)) {
    label <- attr(results, "dr_manifest")$metric %||% "value"
    results <- stats::setNames(list(results), label)
  }
  set_metadata <- NULL
  if (inherits(results, "dr_measurement_set")) {
    validate_measurement_set(results)
    set_metadata <- attr(results, "dr_set_metadata")
    results <- unclass(results)
  }
  dataraft.core::scalar(id, "id")
  dataraft.core::scalar(code_version, "code_version")
  if (
    !is.list(results) ||
      !length(results) ||
      is.null(names(results)) ||
      anyNA(names(results)) ||
      any(!nzchar(names(results))) ||
      anyDuplicated(names(results))
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "results must be a named list."
    )
  }
  measures <- lapply(results, function(x) {
    m <- attr(x, "dr_manifest")
    if (is.null(m)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Use the original dr_measure() result to save a report, before dr_collect() or table edits. The original result retains the calculation and input history."
      )
    }
    if (identical(m$input_published, FALSE)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Trial measurements cannot be saved in reports. Publish the product and recalculate first."
      )
    }
    if (!isTRUE(m$metric_definition$approved)) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Exploratory metrics cannot be saved in reports. After business review, define the metrics with approved = TRUE and code_version = \"your-version\", then dr_measure() again. Approval is your explicit declaration, not an automatic check."
      )
    }
    if (
      !identical(
        m$metric_hash,
        dataraft.core::fingerprint(m$metric_definition)
      ) ||
        !identical(m$metric, m$metric_definition$id) ||
        !identical(m$metric_version, m$metric_definition$version) ||
        !identical(m$product, m$metric_definition$product) ||
        !identical(m$code_version, m$metric_definition$code_version)
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Metric definition changed after calculation. Recalculate before reporting."
      )
    }
    dataraft.core::scalar(m$code_version, "metric code_version")
    if (
      !identical(
        m$result_hash,
        dataraft.core::report_fingerprint(as.data.frame(x))
      )
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Metric result changed after calculation."
      )
    }
    if (
      any(vapply(
        x,
        function(column) {
          is.list(column) || !is.null(dim(column))
        },
        logical(1)
      ))
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Report columns must be atomic vectors. Expand nested metric values into named columns before recalculating and saving a report."
      )
    }
    for (column in x) {
      if (inherits(column, "integer64")) {
        dataraft.core::need("bit64")
        limit <- bit64::as.integer64("9007199254740992")
        if (any(column > limit | column < -limit, na.rm = TRUE)) {
          dataraft.core::abort(
            subclass = "dataraft_error_metrics",
            paste(
              "Report storage cannot preserve these integers exactly.",
              "Integer64 report columns must be within -2^53 to 2^53.",
              "Keep larger values in a storage format with integer64 support."
            )
          )
        }
      }
    }
    values <- as.data.frame(x)
    attr(values, "dr_manifest") <- NULL
    attr(values, "dr_quality_reference") <- NULL
    list(manifest = m, values = values)
  })
  if (is.null(lake)) {
    lake <- measurement_report_destination(results)
  }
  if (!inherits(lake, "dr_lake")) {
    lake <- report_connection(lake, read_only = FALSE)
    on.exit(dataraft.lake::dr_disconnect_lake(lake), add = TRUE)
  }
  dataraft.lake::assert_writable(lake)
  manifest <- list(
    id = id,
    code_version = code_version,
    params = params,
    measures = measures
  )
  if (!is.null(set_metadata)) {
    manifest$measurement_set <- set_metadata
  }
  old <- dataraft.lake::query(
    lake,
    paste(
      "SELECT manifest FROM",
      dataraft.lake::meta(lake, "reports"),
      "WHERE id=?"
    ),
    list(id)
  )
  if (nrow(old)) {
    if (
      !identical(
        report_identity(old$manifest[[1]]),
        report_identity(dataraft.core::report_json(manifest))
      )
    ) {
      dataraft.core::abort(
        subclass = "dataraft_error_metrics",
        "Report id already exists with different content."
      )
    }
    saved <- dataraft.core::jdecode(old$manifest[[1]])
    for (name in names(manifest$measures)) {
      manifest$measures[[name]]$manifest$calculated_at <-
        saved$measures[[name]]$manifest$calculated_at
    }
    return(manifest)
  } else {
    DBI::dbWithTransaction(lake$con, {
      dataraft.lake::insert_meta(
        lake,
        "reports",
        list(
          id = id,
          created_at = dataraft.core::now(),
          manifest = dataraft.core::report_json(manifest)
        )
      )
      for (m in measures) {
        dataraft.lake::insert_meta(
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
  rlang::local_error_call(rlang::caller_env())
  declared <- metric$input_columns
  if (!all(declared %in% available)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Declared metric input columns are missing."
    )
  }
  if (is.null(metric$expr)) {
    return(declared %||% available)
  }
  expression <- rlang::get_expr(metric$expr)
  found <- intersect(all.vars(expression), available)
  dynamic <- FALSE
  visit <- function(x) {
    rlang::local_error_call(rlang::caller_env())
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
          dataraft.core::abort(
            subclass = "dataraft_error_metrics",
            paste("Metric input column is missing:", value)
          )
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
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Dynamic metric expressions require input_columns for missing-value checks."
    )
  }
  union(found, declared)
}


report_identity <- function(json) {
  rlang::local_error_call(rlang::caller_env())
  value <- dataraft.core::jdecode(json)
  value$measures <- lapply(value$measures, function(x) {
    x$manifest$calculated_at <- NULL
    x
  })
  dataraft.core::report_json(value)
}


#' Read an immutable report and its saved results
#'
#' Reads the saved manifest without recalculating any metric. It preserves the
#' original calculation times and works on read-only lakes. Values use the
#' JSON representation stored in the report; dates are ISO strings. With `values_only`, ordinary reports return
#' named result tibbles; batch reports return the long measurement table, with
#' Date selections restored in the `.period` list column.
#' @param lake Connected lake, lake configuration or local lake folder.
#'   Supplied connections remain open; internally opened connections always close.
#' @param id Report release ID.
#' @param values_only Return only the named result tables.
#' @returns A manifest list; with `values_only`, a named list of tibbles for
#'   ordinary reports or a long tibble for batch reports.
#' @export
#' @examples
#' # After saving report.v1 with dr_report_release():
#' # dr_report_read(lake, "report.v1", values_only = TRUE)
dr_report_read <- function(lake, id, values_only = FALSE) {
  if (!inherits(lake, "dr_lake")) {
    lake <- report_connection(lake, read_only = TRUE)
    on.exit(dataraft.lake::dr_disconnect_lake(lake), add = TRUE)
  }
  dataraft.lake::assert_lake(lake)
  dataraft.core::scalar(id, "id")
  dataraft.core::flag(values_only, "values_only")
  row <- dataraft.lake::query(
    lake,
    paste(
      "SELECT manifest FROM",
      dataraft.lake::meta(lake, "reports"),
      "WHERE id = ?"
    ),
    list(id)
  )
  if (nrow(row) != 1L) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      paste("Report not found:", id),
      "dr_no_report"
    )
  }
  manifest <- dataraft.core::jdecode(row$manifest[[1]])
  if (!values_only) {
    return(manifest)
  }
  values <- lapply(manifest$measures, function(x) {
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
  if (is.null(manifest$measurement_set)) {
    return(values)
  }
  metadata <- lapply(manifest$measurement_set, function(x) {
    x["period"] <- list(unlist(x[["period"]], use.names = FALSE))
    if ("Date" %in% unlist(x$period_class)) {
      x$period <- as.Date(x$period)
    }
    x
  })
  for (i in seq_along(values)) {
    attr(values[[i]], "dr_manifest") <- manifest$measures[[i]]$manifest
    attr(values[[i]], "dr_manifest")$by <-
      unlist(manifest$measures[[i]]$manifest$by, use.names = FALSE)
  }
  measurement_set_table(values, metadata)
}
