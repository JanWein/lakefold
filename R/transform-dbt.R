#' Transform staged product input with a dbt model
#'
#' Writes the incoming table to an explicitly named staging relation, closes
#' that connection, runs `dbt build` for the selected model, then opens a fresh
#' connection to read the successfully built relation. The dbt model must
#' reference the supplied staging table; this adapter never ignores its input.
#'
#' `input` is replaced on every execution. Use a dedicated staging table that
#' is not managed by a dbt seed or model, and coordinate concurrent writers.
#' dbt owns SQL dependencies, tests and incremental strategies. Staging and dbt
#' model changes are external side effects; the product's final quality gate
#' controls its publication target, not a rollback of dbt's database changes.
#' The returned table is materialized so every factory-owned connection closes.
#' Invocation ID and selected model are attached as `tw_transform_metadata`.
#' @param project A [tw_dbt_project()] specification.
#' @param model Exact materialized dbt model unique ID, for example
#'   `"model.shop.customer_revenue"`.
#' @param connection Zero-argument function opening a DBI connection to the
#'   database used by dbt. Return a new connection on every call.
#' @param input Dedicated staging table, as a string or [DBI::Id()]. Existing
#'   table contents are replaced. Its schema must already exist.
#' @param full_refresh,vars,echo,timeout Passed to [tw_dbt_build()].
#' @returns A deferred transformation adapter for [tw_add_transform()].
#' @seealso [tw_dbt_init()], [tw_dbt_build()], [tw_source_database()]
#' @export
#' @examples
#' # dbt's selected model must read the dedicated staged_orders relation.
#' project <- tw_dbt_project("analytics", profiles_dir = "analytics")
#' step <- tw_transform_dbt(project, "model.shop.customer_revenue",
#'   connection = function() DBI::dbConnect(duckdb::duckdb(), "analytics.duckdb"),
#'   input = "staged_orders")
#' tw_inspect(step)
tw_transform_dbt <- function(
  project,
  model,
  connection,
  input,
  full_refresh = FALSE,
  vars = list(),
  echo = FALSE,
  timeout = Inf
) {
  if (!inherits(project, "tw_dbt_project")) {
    abort("project must come from tw_dbt_project().")
  }
  scalar(model, "model")
  if (
    !grepl("^model\\.[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$", model)
  ) {
    abort("model must be an exact dbt unique ID such as 'model.shop.orders'.")
  }
  if (!is.function(connection)) {
    abort(
      "connection must be a function opening a new DBI connection; dbt needs R connections closed while it runs."
    )
  }
  if (!inherits(input, "Id")) {
    scalar(input, "input staging table")
  }
  flag(full_refresh, "full_refresh")
  flag(echo, "echo")
  structure(
    list(
      project = project,
      model = model,
      connection = connection,
      input = input,
      full_refresh = full_refresh,
      vars = vars,
      echo = echo,
      timeout = timeout
    ),
    class = "tw_dbt_transform"
  )
}

#' @export
tw_check_component.tw_dbt_transform <- function(x, ...) {
  need("processx")
  if (!file.exists(file.path(x$project$path, "dbt_project.yml"))) {
    abort(
      "The dbt project is missing dbt_project.yml. Check tw_transform_dbt(project = ...)."
    )
  }
  executable <- x$project$executable
  if (!nzchar(Sys.which(executable)) && !file.exists(executable)) {
    abort(
      "Install dbt and set tw_dbt_project(executable = ...) before running this transform."
    )
  }
  invisible(x)
}

#' @export
tw_inspect.tw_dbt_transform <- function(x, ...) {
  list(
    type = "dbt transformation",
    model = x$model,
    input = if (inherits(x$input, "Id")) as.list(x$input@name) else x$input,
    project = x$project$path,
    connection = "factory"
  )
}

#' @export
tw_execute_transform.tw_dbt_transform <- function(transform, data, ...) {
  tw_check_component(transform)
  data <- tw_collect(data)
  with_dbt_connection(transform$connection, function(con) {
    DBI::dbWithTransaction(con, {
      DBI::dbWriteTable(con, transform$input, data, overwrite = TRUE)
    })
  })
  # A package-qualified selector excludes identically named dependency models.
  parts <- strsplit(transform$model, ".", fixed = TRUE)[[1]]
  selector <- paste0(
    "package:",
    parts[[2]],
    ",resource_type:model,fqn:",
    parts[[3]]
  )
  result <- tw_dbt_build(
    transform$project,
    select = selector,
    full_refresh = transform$full_refresh,
    vars = transform$vars,
    echo = transform$echo,
    timeout = transform$timeout
  )
  node <- result$manifest$nodes[[transform$model]]
  succeeded <- result$results$unique_id[result$results$status == "success"]
  if (
    is.null(node) ||
      !identical(node$resource_type, "model") ||
      identical(node$config$materialized, "ephemeral") ||
      !transform$model %in% succeeded
  ) {
    abort(
      "The requested materialized dbt model did not succeed in this build.",
      "tw_dbt_invalid",
      result = result
    )
  }
  relation <- DBI::Id(
    catalog = scalar(node$database, "dbt database"),
    schema = scalar(node$schema, "dbt schema"),
    table = scalar(node$alias %||% node$name, "dbt relation")
  )
  output <- with_dbt_connection(transform$connection, function(con) {
    tibble::as_tibble(DBI::dbReadTable(con, relation))
  })
  attr(output, "tw_transform_metadata") <- list(
    engine = "dbt",
    model = transform$model,
    invocation_id = result$manifest$metadata$invocation_id,
    artifacts_dir = result$artifacts_dir
  )
  output
}

with_dbt_connection <- function(factory, fn) {
  con <- factory()
  if (!inherits(con, "DBIConnection") || !DBI::dbIsValid(con)) {
    abort("The dbt connection factory must return a valid new DBI connection.")
  }
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  fn(con)
}

#' @export
tw_capabilities.tw_dbt_transform <- function(x, ...) {
  tw_component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
