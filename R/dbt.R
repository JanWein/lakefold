#' Describe a dbt project for execution from R
#'
#' Store paths and CLI settings without running dbt or opening a database.
#' dbt remains responsible for SQL models, dependencies, tests and incremental
#' strategies. Use [dl_dbt_build()] or [dl_execute()] to execute the project.
#'
#' @param path Character scalar giving the directory with `dbt_project.yml`.
#'   The directory is checked when executing, not when constructing the object.
#' @param profiles_dir Character scalar pointing to a directory containing
#'   `profiles.yml`, or `NULL` to use dbt's own profile discovery.
#' @param target Optional character scalar naming a target in the dbt profile.
#' @param executable Character scalar giving a dbt executable name or path.
#'   It is passed to [processx::run()] without a shell.
#' @returns A serializable `dl_dbt_project` specification. It contains no
#'   database connection or resolved environment credentials.
#' @seealso [dl_dbt_init()], [dl_dbt_status()], [dl_dbt_model()]
#' @examples
#' project <- dl_dbt_project("analytics", profiles_dir = "analytics")
#' project
#' @export
dl_dbt_project <- function(
  path = "dbt",
  profiles_dir = NULL,
  target = NULL,
  executable = "dbt"
) {
  scalar(executable, "executable")
  if (!is.null(target)) {
    scalar(target, "target")
  }
  structure(
    list(
      path = absolute_path(path),
      profiles_dir = if (is.null(profiles_dir)) {
        NULL
      } else {
        absolute_path(profiles_dir)
      },
      target = target,
      executable = executable
    ),
    class = "dl_dbt_project"
  )
}

#' Build or test SQL models with dbt
#'
#' Run the dbt CLI in a separate process and read that invocation's artifacts.
#' Each invocation gets a new directory under `.lakefold/runs` in the project;
#' a failed invocation can never reuse an earlier run's successful results.
#'
#' Close R connections to the same local DuckDB or DuckLake catalog before
#' running dbt, then reconnect for analysis. dbt manages its own connections.
#' Anonymous usage telemetry is disabled for the child process.
#' A dbt build is not an atomic lakefold release: earlier models can have been
#' materialized even if a later model or test fails. dbt logs and artifacts can
#' contain SQL, paths and database messages; treat them as project data.
#'
#' @param project A [dl_dbt_project()] specification.
#' @param select,exclude Optional character vectors of dbt selection
#'   expressions.
#'   Each element is one CLI argument; expressions starting with `-` are
#'   rejected.
#' @param full_refresh Logical scalar. Rebuild incremental models when `TRUE`.
#' @param vars A named list of non-secret dbt variables, encoded as JSON.
#' @param echo Logical scalar. Stream dbt output to the R console.
#' @param timeout Positive timeout in seconds, or `Inf` for no limit.
#' @param stop_on_failure Logical scalar. Raise `dl_dbt_failed` on a nonzero
#'   exit
#'   status, failed nodes or missing artifacts. The condition's `result` field
#'   retains diagnostics. Set `FALSE` to inspect failures as ordinary results.
#' @returns A `dl_dbt_result` list with `status` (integer exit code), `success`
#'   (logical), `command`, `results` (node tibble), parsed `manifest`,
#'   `artifacts_dir`, `stdout`, `stderr` and `artifact_error`. Warnings reported
#'   by dbt are retained and do not by themselves count as failure.
#' @seealso [dl_dbt_status()], [dl_dbt_lineage()], [dl_dbt_model()]
#' @examplesIf nzchar(Sys.getenv("LAKEFOLD_DBT_EXAMPLE_PROJECT"))
#' project <- dl_dbt_project(Sys.getenv("LAKEFOLD_DBT_EXAMPLE_PROJECT"))
#' result <- dl_dbt_build(project, select = "tag:reporting", echo = FALSE)
#' dl_dbt_status(result)
#' @export
dl_dbt_build <- function(
  project,
  select = NULL,
  exclude = NULL,
  full_refresh = FALSE,
  vars = list(),
  echo = TRUE,
  timeout = Inf,
  stop_on_failure = TRUE
) {
  dbt_run(
    project,
    "build",
    select,
    exclude,
    full_refresh,
    vars,
    echo,
    timeout,
    stop_on_failure
  )
}

#' @rdname dl_dbt_build
#' @export
dl_dbt_test <- function(
  project,
  select = NULL,
  exclude = NULL,
  vars = list(),
  echo = TRUE,
  timeout = Inf,
  stop_on_failure = TRUE
) {
  dbt_run(
    project,
    "test",
    select,
    exclude,
    FALSE,
    vars,
    echo,
    timeout,
    stop_on_failure
  )
}

#' @export
dl_execute.dl_dbt_project <- function(object, lake = NULL, ...) {
  if (!is.null(lake)) {
    abort("dbt opens its own connections; omit lake.", "dl_dbt_invalid")
  }
  dl_dbt_build(object, ...)
}

flag <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    abort(paste(name, "must be TRUE or FALSE."), "dl_dbt_invalid")
  }
  value
}

dbt_selection <- function(value, name) {
  if (is.null(value)) {
    return(character())
  }
  if (
    !is.character(value) ||
      !length(value) ||
      anyNA(value) ||
      any(!nzchar(trimws(value))) ||
      any(startsWith(trimws(value), "-"))
  ) {
    abort(
      paste(name, "must contain non-empty dbt selectors, not CLI flags."),
      "dl_dbt_invalid"
    )
  }
  c(paste0("--", name), value)
}

dbt_process <- function(command, args, wd, echo, timeout) {
  processx::run(
    command,
    args,
    wd = wd,
    echo = echo,
    timeout = timeout,
    error_on_status = FALSE,
    cleanup_tree = TRUE,
    env = c(
      "current",
      DBT_SEND_ANONYMOUS_USAGE_STATS = "false",
      DBT_ENGINE_SEND_ANONYMOUS_USAGE_STATS = "false",
      DO_NOT_TRACK = "1"
    )
  )
}

dbt_run <- function(
  project,
  command,
  select,
  exclude,
  full_refresh,
  vars,
  echo,
  timeout,
  stop_on_failure
) {
  if (!inherits(project, "dl_dbt_project")) {
    abort("Use dl_dbt_project() first.", "dl_dbt_invalid")
  }
  flag(full_refresh, "full_refresh")
  flag(echo, "echo")
  flag(stop_on_failure, "stop_on_failure")
  if (
    !is.numeric(timeout) ||
      length(timeout) != 1L ||
      is.na(timeout) ||
      timeout <= 0
  ) {
    abort(
      "timeout must be a positive number of seconds or Inf.",
      "dl_dbt_invalid"
    )
  }
  if (
    !is.list(vars) ||
      (length(vars) &&
        (is.null(names(vars)) ||
          anyNA(names(vars)) ||
          any(!nzchar(names(vars))) ||
          anyDuplicated(names(vars))))
  ) {
    abort(
      "vars must be a named list with unique non-empty names.",
      "dl_dbt_invalid"
    )
  }
  selectors <- c(
    dbt_selection(select, "select"),
    dbt_selection(exclude, "exclude")
  )
  if (!file.exists(file.path(project$path, "dbt_project.yml"))) {
    abort(
      "No dbt_project.yml found. Use dl_dbt_init() or supply an existing project.",
      "dl_dbt_invalid"
    )
  }
  need("processx")
  executable <- Sys.which(project$executable)
  if (!nzchar(executable) && !file.exists(project$executable)) {
    abort(
      "dbt executable not found. Install dbt and set executable to its path.",
      "dl_dbt_unavailable"
    )
  }
  artifacts <- file.path(project$path, ".lakefold", "runs", uid())
  if (!dir.create(artifacts, recursive = TRUE)) {
    abort("Could not create the dbt artifact directory.", "dl_dbt_io")
  }
  args <- c(
    command,
    "--project-dir",
    project$path,
    "--target-path",
    artifacts,
    "--log-path",
    file.path(artifacts, "logs"),
    selectors
  )
  if (!is.null(project$profiles_dir)) {
    args <- c(args, "--profiles-dir", project$profiles_dir)
  }
  if (!is.null(project$target)) {
    args <- c(args, "--target", project$target)
  }
  if (full_refresh) {
    args <- c(args, "--full-refresh")
  }
  if (length(vars)) {
    args <- c(
      args,
      "--vars",
      as.character(jsonlite::toJSON(vars, auto_unbox = TRUE))
    )
  }
  process <- tryCatch(
    dbt_process(project$executable, args, project$path, echo, timeout),
    error = function(e) {
      abort(
        "dbt could not complete. Check the executable, timeout and project logs.",
        "dl_dbt_process_error",
        parent = e,
        artifacts_dir = artifacts
      )
    }
  )
  result <- structure(
    list(
      command = command,
      status = as.integer(process$status),
      success = FALSE,
      results = dbt_empty_results(),
      manifest = NULL,
      artifacts_dir = artifacts,
      stdout = process$stdout,
      stderr = process$stderr,
      artifact_error = NULL
    ),
    class = "dl_dbt_result"
  )
  parsed <- tryCatch(dbt_read_artifacts(artifacts), error = identity)
  if (inherits(parsed, "error")) {
    result$artifact_error <- conditionMessage(parsed)
  } else {
    result$results <- parsed$results
    result$manifest <- parsed$manifest
    result$success <- identical(result$status, 0L) &&
      all(result$results$status %in% c("success", "pass", "warn"))
  }
  if (stop_on_failure && !result$success) {
    abort(
      "dbt execution failed. Inspect condition$result or use stop_on_failure = FALSE.",
      "dl_dbt_failed",
      result = result
    )
  }
  result
}

dbt_empty_results <- function() {
  tibble::tibble(
    unique_id = character(),
    status = character(),
    execution_time = double(),
    failures = integer(),
    message = character()
  )
}

dbt_read_json <- function(path) {
  if (!file.exists(path)) {
    abort(
      paste("Missing dbt artifact:", basename(path)),
      "dl_dbt_artifact_invalid"
    )
  }
  tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      abort(
        paste("Invalid dbt JSON:", basename(path)),
        "dl_dbt_artifact_invalid"
      )
    }
  )
}

dbt_read_artifacts <- function(path) {
  runs <- dbt_read_json(file.path(path, "run_results.json"))
  manifest <- dbt_read_manifest(path)
  if (!is.list(runs) || is.null(runs$metadata) || !is.list(runs$results)) {
    abort(
      "run_results.json must contain metadata and a results array.",
      "dl_dbt_artifact_invalid"
    )
  }
  run_id <- runs$metadata$invocation_id
  manifest_id <- manifest$metadata$invocation_id
  if (
    is.null(run_id) || is.null(manifest_id) || !identical(run_id, manifest_id)
  ) {
    abort(
      "dbt artifacts must belong to the same invocation.",
      "dl_dbt_artifact_invalid"
    )
  }
  rows <- lapply(runs$results, function(node) {
    if (
      !is.list(node) ||
        !is.character(node$unique_id) ||
        length(node$unique_id) != 1L ||
        !is.character(node$status) ||
        length(node$status) != 1L
    ) {
      abort(
        "A dbt result is missing unique_id or status.",
        "dl_dbt_artifact_invalid"
      )
    }
    for (field in c("execution_time", "failures", "message")) {
      value <- node[[field]]
      valid <- is.null(value) ||
        (length(value) == 1L &&
          if (field == "message") is.character(value) else is.numeric(value))
      if (!valid) {
        abort(
          paste("Invalid scalar dbt result field:", field),
          "dl_dbt_artifact_invalid"
        )
      }
    }
    tibble::tibble(
      unique_id = node$unique_id,
      status = node$status,
      execution_time = as.double(node$execution_time %||% NA_real_),
      failures = as.integer(node$failures %||% NA_integer_),
      message = as.character(node$message %||% NA_character_)
    )
  })
  list(
    results = if (length(rows)) dplyr::bind_rows(rows) else dbt_empty_results(),
    manifest = manifest
  )
}

dbt_read_manifest <- function(path) {
  manifest <- dbt_read_json(file.path(path, "manifest.json"))
  if (
    !is.list(manifest) ||
      !is.list(manifest$nodes) ||
      !is.list(manifest$metadata)
  ) {
    abort(
      "manifest.json must contain metadata and nodes.",
      "dl_dbt_artifact_invalid"
    )
  }
  manifest
}

#' Inspect the node results of a dbt invocation
#'
#' Read structured statuses without parsing console output. A directory must
#' contain a matching pair of `run_results.json` and `manifest.json` artifacts.
#' The returned table contains executed nodes only, not the entire dbt project.
#' @param x A `dl_dbt_result`, or a character scalar giving an artifact
#'   directory.
#' @returns A tibble with character columns `unique_id`, `status`, `message`,
#'   numeric `execution_time` (seconds) and integer `failures` (possibly `NA`).
#' @seealso [dl_dbt_build()], [dl_dbt_lineage()]
#' @examples
#' artifacts <- system.file("extdata", "dbt-artifacts", package = "lakefold")
#' dl_dbt_status(artifacts)
#' @export
dl_dbt_status <- function(x) {
  if (inherits(x, "dl_dbt_result")) {
    return(x$results)
  }
  dbt_read_artifacts(absolute_path(x))$results
}

#' Extract dependency edges from a dbt manifest
#'
#' Return declared dependencies for models, tests, sources, exposures and other
#' manifest nodes. Dependencies describe SQL builds, not primary/foreign keys
#' or column-level lineage. No database connection or dbt installation is
#'   needed.
#' @inheritParams dl_dbt_status
#' @returns A tibble with character columns `from`, `to` and `resource_type`.
#'   One row represents a dependency from a parent to a downstream resource.
#' @seealso [dl_dbt_model()], [dl_dbt_status()]
#' @examples
#' artifacts <- system.file("extdata", "dbt-artifacts", package = "lakefold")
#' dl_dbt_lineage(artifacts)
#' @export
dl_dbt_lineage <- function(x) {
  manifest <- dbt_manifest(x)
  nodes <- c(
    manifest$nodes,
    manifest$sources,
    manifest$exposures,
    manifest$metrics,
    manifest$semantic_models,
    manifest$saved_queries
  )
  rows <- lapply(names(nodes), function(id) {
    parents <- unlist(nodes[[id]]$depends_on$nodes, use.names = FALSE)
    if (!length(parents)) {
      return(NULL)
    }
    tibble::tibble(
      from = as.character(parents),
      to = id,
      resource_type = nodes[[id]]$resource_type %||% "unknown"
    )
  })
  out <- dplyr::bind_rows(rows)
  if (!nrow(out)) {
    return(tibble::tibble(
      from = character(),
      to = character(),
      resource_type = character()
    ))
  }
  unique(out)
}

dbt_manifest <- function(x) {
  if (inherits(x, "dl_dbt_result")) {
    if (is.null(x$manifest)) {
      abort("This dbt result has no valid manifest.", "dl_dbt_artifact_invalid")
    }
    return(x$manifest)
  }
  dbt_read_manifest(absolute_path(x))
}

#' Open materialized dbt relations as a lazy relational model
#'
#' Build a [dm::dm()] from explicit relation names in a dbt manifest. The lake
#' must refer to the same catalog used by the dbt project. SQL dependencies do
#' not imply relational keys; declare keys explicitly when needed.
#'
#' Relations are current dbt tables or views, not immutable lakefold releases.
#' The returned lazy model borrows the supplied connection; keep it open while
#' querying. Ephemeral models cannot be opened. This function does not certify
#' that tables were successfully built or that they still match the artifacts.
#' @param lake A connected lake from [dl_connect()].
#' @inheritParams dl_dbt_status
#' @param tables Optional named character vector mapping R table aliases to dbt
#'   unique IDs, such as `c(sales = "model.shop.sales")`. By default includes
#'   all
#'   non-ephemeral models, seeds and snapshots. Use a subset after selected
#'   builds.
#' @param database Character scalar: the attachment name in the R connection.
#'   Defaults to `"lake"`, as created by [dl_connect()].
#' @inheritParams dl_model
#' @returns A lazy `dm` object with a `dl_dbt_nodes` attribute mapping aliases
#'   to dbt unique IDs. Key violations raise `dl_model_invalid` when `check` is
#'   `TRUE`; SQL and connection errors are propagated.
#' @seealso [dl_model()] for immutable releases, [dl_dbt_lineage()]
#' @examplesIf nzchar(Sys.getenv("LAKEFOLD_DBT_EXAMPLE_PROJECT"))
#' # See vignette("dbt-workflows") for a complete build and reconnect example.
#' project <- dl_dbt_project(Sys.getenv("LAKEFOLD_DBT_EXAMPLE_PROJECT"))
#' project
#' @export
dl_dbt_model <- function(
  lake,
  x,
  tables = NULL,
  database = "lake",
  primary_keys = list(),
  foreign_keys = list(),
  check = TRUE
) {
  assert_lake(lake)
  need("dm")
  scalar(database, "database")
  flag(check, "check")
  manifest <- dbt_manifest(x)
  available <- Filter(
    function(node) {
      node$resource_type %in%
        c("model", "seed", "snapshot") &&
        !identical(node$config$materialized, "ephemeral")
    },
    manifest$nodes
  )
  if (is.null(tables)) {
    tables <- stats::setNames(
      names(available),
      vapply(available, function(node) node$alias %||% node$name, character(1))
    )
  }
  if (
    !is.character(tables) ||
      !length(tables) ||
      anyNA(tables) ||
      is.null(names(tables)) ||
      anyNA(names(tables)) ||
      any(!nzchar(names(tables))) ||
      anyDuplicated(names(tables)) ||
      !all(tables %in% names(available))
  ) {
    abort(
      "tables must map unique R aliases to materialized dbt node IDs.",
      "dl_dbt_invalid"
    )
  }
  relations <- lapply(tables, function(id) {
    node <- available[[id]]
    schema <- scalar(node$schema, "dbt schema")
    table <- scalar(node$alias %||% node$name, "dbt relation name")
    dplyr::tbl(
      lake$con,
      DBI::Id(catalog = database, schema = schema, table = table)
    )
  })
  model <- dm_keys(dm::dm(!!!relations), primary_keys, foreign_keys, check)
  attr(model, "dl_dbt_nodes") <- tables
  model
}

#' @export
print.dl_dbt_project <- function(x, ...) {
  cat(
    "<dl_dbt_project>\nProject:",
    x$path,
    "\nTarget:",
    x$target %||% "profile default",
    "\n"
  )
  invisible(x)
}
#' @export
print.dl_dbt_result <- function(x, ...) {
  cat(
    "<dl_dbt_result>",
    x$command,
    "| exit:",
    x$status,
    "|",
    if (x$success) "success" else "failed",
    "\n"
  )
  print(x$results)
  if (!is.null(x$artifact_error)) {
    cat("Artifacts:", x$artifact_error, "\n")
  }
  invisible(x)
}
