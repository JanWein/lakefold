#' Inspect execution status across R and dbt workflows
#' @param x A connected lake, [run()] result, [dbt_build()] result or a
#'   measurement set from [measure()].
#' @param asset Optional asset ID when querying a lake.
#' @returns A tibble with `engine`, `id`, `status`, `success`, `release_id`,
#'   `asset`, `outcome` and `message`. `outcome` normalizes native statuses to
#'   `succeeded`, `blocked`, `failed` or `skipped` (unknown states are `NA`).
#'   Missing deliveries are `blocked` because no acceptable input is available.
#'   A dbt process failure remains visible even when
#'   individual nodes passed. No raw stdout or stderr is included.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-")
#' lake <- connect_lake(lake_config(registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"))
#' status(lake)
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
status <- function(x, asset = NULL) {
  if (inherits(x, "tw_measurement_set")) {
    validate_measurement_set(x)
    return(dplyr::bind_rows(lapply(x, function(value) {
      manifest <- attr(value, "tw_manifest")
      tibble::tibble(
        engine = "tidyweave",
        id = manifest$metric,
        status = "completed",
        outcome = "succeeded",
        success = TRUE,
        release_id = manifest$release_id,
        asset = manifest$product,
        message = ""
      )
    })))
  }
  if (inherits(x, "tw_lake")) {
    runs <- metadata_filter(x, "runs", asset = asset)
    runs <- runs[order(runs$started_at, decreasing = TRUE), ]
    return(tibble::tibble(
      engine = rep("tidyweave", nrow(runs)),
      id = runs$run_id,
      status = runs$status,
      outcome = status_outcome(runs$status),
      success = runs$status %in% c("published", "cached"),
      release_id = runs$release_id,
      asset = runs$asset,
      message = runs$message
    ))
  }
  if (inherits(x, "tw_run_result")) {
    return(tibble::tibble(
      engine = "tidyweave",
      id = x$run_id,
      status = x$status,
      outcome = status_outcome(x$status),
      success = x$status %in% c("completed", "published", "cached"),
      release_id = x$release_id,
      asset = x$asset %||% NA_character_,
      message = ""
    ))
  }
  if (inherits(x, "tw_dbt_result")) {
    nodes <- x$results
    rows <- tibble::tibble(
      engine = rep("dbt", nrow(nodes)),
      id = nodes$unique_id,
      status = nodes$status,
      outcome = status_outcome(nodes$status),
      success = nodes$status %in% c("success", "pass", "warn"),
      release_id = rep(NA_character_, nrow(nodes)),
      asset = nodes$unique_id,
      message = rep("", nrow(nodes))
    )
    if (!isTRUE(x$success)) {
      rows <- dplyr::bind_rows(
        rows,
        tibble::tibble(
          engine = "dbt",
          id = ".process",
          status = "error",
          outcome = "failed",
          success = FALSE,
          release_id = NA_character_,
          asset = NA_character_,
          message = "dbt execution or artifact verification failed; inspect the local result."
        )
      )
    }
    return(rows)
  }
  abort(
    "x must be a lake, tidyweave run result, measurement set or dbt result."
  )
}

metadata_filter <- function(lake, table, asset = NULL, run_id = NULL) {
  assert_lake(lake)
  filters <- character()
  params <- list()
  if (!is.null(asset)) {
    asset_id(asset)
    filters <- c(filters, "asset = ?")
    params <- c(params, list(asset))
  }
  if (!is.null(run_id)) {
    scalar(run_id, "run_id")
    filters <- c(filters, "run_id = ?")
    params <- c(params, list(run_id))
  }
  sql <- paste("SELECT * FROM", meta(lake, table))
  if (length(filters)) {
    sql <- paste(sql, "WHERE", paste(filters, collapse = " AND "))
  }
  query(lake, sql, if (length(params)) params else NULL)
}

#' Retrieve quality evidence for a run or release
#'
#' An asset selects its latest attempt, while `release` selects the evidence
#' for that exact published stand. Cached runs resolve to the original release's
#' checks. These choices prevent an older successful run hiding a recent
#' failure.
#' @param x A lake, run result, dbt result or quality tibble.
#' @param run_id Run ID when `x` is a lake.
#' @param asset Asset ID. Required with `release`; otherwise selects the latest
#'   attempt. Supply at most one of `run_id` and `asset`.
#' @param release Exact release ID to inspect, together with `asset`.
#' @returns A quality tibble. `failure_rate` is derived from available counts.
#'   Native pointblank thresholds are recorded in the JSON `details` column.
#' @seealso [quality_report()], [status()]
#' @export
#' @examples
#' contract <- contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' quality(validate(data.frame(id = c(1L, 1L)), contract))
quality <- function(x, run_id = NULL, asset = NULL, release = NULL) {
  if (inherits(x, "tw_measurement_set")) {
    abort(
      "Measurement sets retain input quality summaries, not full checks. Use quality(lake, asset = ..., release = ...) for the exact input release."
    )
  }
  if (inherits(x, "tw_lake")) {
    if (
      is.null(run_id) == is.null(asset) || (!is.null(release) && is.null(asset))
    ) {
      abort("Supply run_id, or asset with an optional exact release.")
    }
    if (!is.null(release)) {
      run_id <- resolve_release(x, asset, release)$run_id[[1]]
    } else {
      runs <- metadata_filter(x, "runs", asset = asset, run_id = run_id)
      if (!nrow(runs)) {
        abort("No matching run found.", "tw_no_run")
      }
      runs <- runs[order(runs$started_at, runs$run_id, decreasing = TRUE), ]
      run_id <- runs$run_id[[1]]
      if (runs$status[[1]] == "cached") {
        run_id <- resolve_release(
          x,
          runs$asset[[1]],
          runs$release_id[[1]]
        )$run_id[[1]]
      }
    }
    out <- metadata_filter(x, "quality_results", run_id = run_id)
  } else if (inherits(x, "tw_run_result")) {
    if (is.null(x$quality)) {
      abort(
        "This result has no in-memory checks; use quality(lake, run_id = ...)."
      )
    }
    out <- x$quality
  } else if (inherits(x, "tw_dbt_result")) {
    states <- status(x)
    out <- dplyr::bind_rows(lapply(seq_len(nrow(states)), function(i) {
      node <- states[i, ]
      status <- if (node$status %in% c("pass", "success")) {
        "passed"
      } else if (node$status == "warn") {
        "warning"
      } else if (node$status == "fail") {
        "failed"
      } else if (node$status == "skipped") {
        "not_checked"
      } else {
        "error"
      }
      ix <- match(node$id, x$results$unique_id)
      quality_row(
        node$id,
        status,
        if (status == "warning") "warning" else "error",
        n_failed = if (is.na(ix)) NA_real_ else x$results$failures[[ix]],
        threshold = NA_real_,
        engine = "dbt",
        stage = "model",
        message = node$message
      )
    }))
    if (!nrow(out)) {
      out <- quality_row(
        "dbt",
        "not_checked",
        engine = "dbt",
        stage = "model",
        message = "No executed nodes."
      )
    }
  } else if (
    is.data.frame(x) &&
      all(c("rule", "status", "n_failed", "n_total") %in% names(x))
  ) {
    out <- x
  } else {
    abort("x must be quality results, a lake, a run result or a dbt result.")
  }
  out$failure_rate <- ifelse(
    is.finite(out$n_total) & out$n_total > 0,
    out$n_failed / out$n_total,
    NA_real_
  )
  out
}

#' List published release history
#' @param lake Connected lake.
#' @param asset Optional asset ID.
#' @returns A tibble sorted newest first. Historical releases are retained.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-")
#' lake <- connect_lake(lake_config(registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"))
#' releases(lake)
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
releases <- function(lake, asset = NULL) {
  out <- metadata_filter(lake, "releases", asset = asset)
  out[order(out$published_at, out$release_id, decreasing = TRUE), ]
}

#' Follow declared dataset lineage
#'
#' Traverses dataset IDs while retaining version IDs on each returned edge.
#' It does not infer column lineage or reconstruct a single historical DAG.
#' Run results expose only recorded inputs for that exact execution, without
#' querying the latest lake state or inferring unrecorded upstream edges.
#' @param x Connected lake, run result, measurement set, dbt result or dbt
#'   artifact directory. Measurement edges describe the input release and
#'   metric version; they have no execution run ID.
#' @param asset Optional starting dataset ID (dbt unique ID for dbt inputs).
#' @param direction Follow upstream inputs or downstream consumers.
#' @param recursive Follow all reachable edges, with cycle protection.
#' @returns A tibble of lineage edges with endpoint IDs and versions. dbt edges
#'   have empty version fields because a manifest declares dependencies.
#' @export
#' @examples
#' path <- system.file("extdata", "dbt-artifacts", package = "tidyweave")
#' lineage(path, "model.shop.customer_revenue")
lineage <- function(
  x,
  asset = NULL,
  direction = c("upstream", "downstream"),
  recursive = TRUE
) {
  direction <- match.arg(direction)
  flag(recursive, "recursive")
  if (inherits(x, "tw_lake")) {
    edges <- registry(x, "lineage_edges")
  } else if (inherits(x, "tw_run_result")) {
    edges <- run_result_lineage(x)
  } else if (inherits(x, "tw_measurement_set")) {
    validate_measurement_set(x)
    edges <- unique(dplyr::bind_rows(lapply(x, function(value) {
      manifest <- attr(value, "tw_manifest")
      tibble::tibble(
        run_id = NA_character_,
        from_id = manifest$product,
        from_version = manifest$release_id,
        to_id = manifest$metric,
        to_version = manifest$metric_version,
        relation = "measured_from"
      )
    })))
  } else {
    source <- dbt_lineage(x)
    edges <- tibble::tibble(
      run_id = rep("", nrow(source)),
      from_id = source$from,
      from_version = rep("", nrow(source)),
      to_id = source$to,
      to_version = rep("", nrow(source)),
      relation = rep("dbt_dependency", nrow(source))
    )
  }
  if (is.null(asset)) {
    return(edges)
  }
  scalar(asset, "asset")
  start <- if (direction == "upstream") "to_id" else "from_id"
  end <- if (direction == "upstream") "from_id" else "to_id"
  frontier <- asset
  seen <- character()
  selected <- rep(FALSE, nrow(edges))
  while (length(frontier)) {
    found <- edges[[start]] %in% frontier
    selected <- selected | found
    if (!recursive) {
      break
    }
    seen <- union(seen, frontier)
    frontier <- setdiff(unique(edges[[end]][found]), seen)
  }
  edges[selected, ]
}


status_outcome <- function(status) {
  out <- rep(NA_character_, length(status))
  out[
    status %in% c("completed", "published", "cached", "success", "pass", "warn")
  ] <- "succeeded"
  out[status %in% c("blocked", "fail", "missing")] <- "blocked"
  out[status %in% c("error", "failed", "runtime error")] <- "failed"
  out[status %in% c("skipped", "skip")] <- "skipped"
  out
}

empty_lineage <- function() {
  tibble::tibble(
    run_id = character(),
    from_id = character(),
    from_version = character(),
    to_id = character(),
    to_version = character(),
    relation = character()
  )
}

run_result_lineage <- function(x) {
  recorded <- x$metadata$lineage
  if (is.data.frame(recorded)) {
    return(tibble::as_tibble(recorded)[names(empty_lineage())])
  }
  inputs <- x$source_inputs %||% x$inputs
  destination <- x$asset %||% x$metadata$product
  if (
    !is.data.frame(inputs) ||
      !all(c("asset", "run_id", "release_id") %in% names(inputs)) ||
      is.null(destination)
  ) {
    return(empty_lineage())
  }
  known <- !is.na(inputs$asset) & nzchar(inputs$asset)
  inputs <- inputs[known, , drop = FALSE]
  if (!nrow(inputs)) {
    return(empty_lineage())
  }
  version <- function(release, run) {
    ifelse(!is.na(release) & nzchar(release), release, run)
  }
  unique(tibble::tibble(
    run_id = rep(x$run_id, nrow(inputs)),
    from_id = inputs$asset,
    from_version = version(inputs$release_id, inputs$run_id),
    to_id = rep(destination, nrow(inputs)),
    to_version = rep(version(x$release_id, x$run_id), nrow(inputs)),
    relation = rep("consumed_from", nrow(inputs))
  ))
}
