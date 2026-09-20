#' Read a source using an interchangeable adapter
#'
#' Data frames and zero-argument functions work directly. File paths are
#' normalized by [add_source()]. A source method returns a data frame or
#' tibble or a lazy table. Use a function to call an API or another existing client.
#' @param source Source object, data frame or zero-argument function.
#' @param ... Adapter-specific options.
#' @returns A data frame or tibble. Connections supplied by callers stay open.
#' @export
#' @examples
#' read_source(function() data.frame(id = 1:2))
read_source <- function(source, ...) UseMethod("read_source")
#' @export
read_source.data.frame <- function(source, ...) source
#' @export
read_source.function <- function(source, ...) source()
#' @export
read_source.tw_source <- function(source, ...) source$reader(source$path)
#' @export
read_source.default <- function(source, ...) {
  abort(
    "This source needs a read_source() method. You can also pass a function returning a data frame."
  )
}

#' Describe a DBI table or SQL query as a source
#'
#' Supply exactly one of `table` and `query`. The connection may be an open DBI
#' connection or a zero-argument factory. Only factory-created connections are
#' closed by tidyweave. SQL is passed to DBI unchanged; use `params` for values.
#' Nothing is queried during construction or structural preflight.
#' @param connection DBI connection or function opening one.
#' @param table Table name or [DBI::Id()].
#' @param query A single SQL query string.
#' @param params Parameters passed to [DBI::dbGetQuery()]. Parameterized
#'   queries are materialized, because DBI binding is not a lazy query.
#' @param lazy Keep a caller-owned DBI table lazy. Defaults to `TRUE` for open
#'   connections without parameters and `FALSE` for factories. Factories are
#'   closed before returning and cannot provide lazy output.
#' @returns A source specification accepted by [add_source()].
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
#' DBI::dbWriteTable(con, "orders", data.frame(id = 1:2))
#' read_source(source_database(con, table = "orders"))
#' DBI::dbDisconnect(con, shutdown = TRUE)
source_database <- function(
  connection,
  table = NULL,
  query = NULL,
  params = NULL,
  lazy = !is.function(connection) && is.null(params)
) {
  flag(lazy, "lazy")
  if (lazy && (is.function(connection) || !is.null(params))) {
    abort("Use lazy = FALSE for connection factories or parameterized queries.")
  }
  if (is.null(table) == is.null(query)) {
    abort("Supply exactly one of table or query.")
  }
  if (!is.function(connection) && !inherits(connection, "DBIConnection")) {
    abort("connection must be a DBI connection or a function opening one.")
  }
  if (!is.null(table) && !inherits(table, "Id")) {
    scalar(table, "table")
  }
  if (!is.null(query)) {
    scalar(query, "query")
  }
  if (!is.null(params) && is.null(query)) {
    abort("params requires a SQL query.")
  }
  structure(
    list(
      connection = connection,
      table = table,
      query = query,
      params = params,
      lazy = lazy
    ),
    class = "tw_database_source"
  )
}
#' @export
read_source.tw_database_source <- function(source, ...) {
  con <- source$connection
  if (is.function(con)) {
    con <- con()
    if (!inherits(con, "DBIConnection")) {
      abort("The connection factory must return a DBI connection.")
    }
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }
  if (!DBI::dbIsValid(con)) {
    abort(
      "The source connection is closed. Open it or supply a connection factory."
    )
  }
  if (isTRUE(source$lazy)) {
    relation <- if (!is.null(source$table)) {
      source$table
    } else {
      dbplyr::sql(source$query)
    }
    return(dplyr::tbl(con, relation))
  }
  if (!is.null(source$table)) {
    DBI::dbReadTable(con, source$table)
  } else if (is.null(source$params)) {
    DBI::dbGetQuery(con, source$query)
  } else {
    DBI::dbGetQuery(con, source$query, params = source$params)
  }
}

#' Execute an interchangeable transformation
#'
#' Ordinary functions receive and return a data frame, tibble or lazy table.
#' With multiple sources, the first transform receives a named list of tables. Extension methods may delegate to existing tools. They must return
#' a data frame or tibble. No transformation class is required for R functions.
#' @param transform Function or adapter object.
#' @param data Input data frame.
#' @param ... Adapter-specific options.
#' @returns A data frame or tibble.
#' @export
#' @examples
#' execute_transform(function(data) transform(data, doubled = amount * 2),
#'   data.frame(amount = 10))
execute_transform <- function(transform, data, ...) {
  UseMethod("execute_transform")
}
#' @export
execute_transform.function <- function(transform, data, ...) transform(data)
#' @export
execute_transform.default <- function(transform, data, ...) {
  abort(
    "This transformation needs a execute_transform() method. An ordinary R function also works."
  )
}

# Auxiliary inputs belong to their transformation, not to the primary table.
component_sources <- function(x, ...) UseMethod("component_sources")
#' @export
component_sources.default <- function(x, ...) list()

replace_component_sources <- function(x, sources, ...) {
  UseMethod("replace_component_sources")
}
#' @export
replace_component_sources.default <- function(x, sources, ...) {
  if (length(sources)) {
    abort("This component cannot replace its dependencies.")
  }
  x
}

transform_source_names <- function(step, sources) {
  if (!length(sources)) {
    return(character())
  }
  if (
    is.null(names(sources)) ||
      anyNA(names(sources)) ||
      any(!nzchar(names(sources))) ||
      anyDuplicated(names(sources))
  ) {
    abort("Transformation dependencies must have unique, non-empty names.")
  }
  paste0("transform:", step, ":", names(sources))
}

product_sources <- function(product) {
  sources <- product$sources
  for (step in names(product$transforms)) {
    auxiliary <- component_sources(product$transforms[[step]])
    labels <- transform_source_names(step, auxiliary)
    if (any(labels %in% names(sources))) {
      abort("A source name conflicts with a transformation dependency.")
    }
    sources <- c(sources, stats::setNames(auxiliary, labels))
  }
  sources
}

replace_product_sources <- function(product, sources) {
  product$sources <- sources[names(product$sources)]
  for (step in names(product$transforms)) {
    auxiliary <- component_sources(product$transforms[[step]])
    if (!length(auxiliary)) {
      next
    }
    labels <- transform_source_names(step, auxiliary)
    product$transforms[[step]] <- replace_component_sources(
      product$transforms[[step]],
      stats::setNames(sources[labels], names(auxiliary))
    )
  }
  product
}

normalize_result_source <- function(result) {
  if (!result$status %in% c("completed", "published", "cached")) {
    abort("Use a successful run as a source. This run has no approved output.")
  }
  pinned <- length(result$release_id) == 1L &&
    !is.na(result$release_id) &&
    nzchar(result$release_id)
  destination <- result$output_config %||% result$output_lake
  if (pinned && !is.null(destination)) {
    source <- source_release(destination, result$asset, result$release_id)
    source$output_lake <- result$output_lake
    source$run_id <- result$run_id
    return(source)
  }
  if (is.null(result$data)) {
    abort(
      "This successful run has neither submitted data nor a readable release reference."
    )
  }
  structure(
    list(data = result$data, asset = result$asset, run_id = result$run_id),
    class = "tw_result_source"
  )
}

#' @export
read_source.tw_result_source <- function(source, ...) {
  data <- source$data
  attr(data, "tw_input_reference") <- list(
    asset = source$asset,
    run_id = source$run_id
  )
  data
}
#' @export
check_component.tw_result_source <- function(x, ...) {
  assert_component(x$data, "read_source")
  invisible(x)
}
#' @export
inspect.tw_result_source <- function(x, ...) {
  data <- inspect(x$data)
  data$rows <- NULL
  list(type = "accepted run", asset = x$asset, data = data)
}

#' Apply a DuckDB SQL query to a data frame
#'
#' The input is available as `data` in a private, temporary DuckDB connection.
#' SQL is executed unchanged by DuckDB and must return a table. This adapter is
#' intended for trusted analytical queries; it does not sandbox SQL.
#' @param query SQL query referencing the input table `data`.
#' @returns A transformation accepted by [add_transform()].
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' product("totals") |>
#'   add_source(data.frame(amount = c(10, 20))) |>
#'   add_transform(sql_transform("SELECT sum(amount) AS total FROM data")) |>
#'   run() |>
#'   collect()
sql_transform <- function(query) {
  structure(list(query = scalar(query, "query")), class = "tw_sql_transform")
}
#' @export
execute_transform.tw_sql_transform <- function(transform, data, ...) {
  need("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "data", as.data.frame(data))
  DBI::dbGetQuery(con, transform$query)
}

#' Check a component before execution
#'
#' Extension packages implement this S3 generic alongside their read, transform,
#' quality, target or catalog method. Validate configuration and dependencies;
#' do not fetch data, execute user callbacks or write anything. Return `x`
#' invisibly or raise an actionable error. Passing preflight does not prove
#' that remote resources are available or that the data meet their contract.
#' @param x Component to inspect.
#' @param ... Reserved for adapter options.
#' @returns `x`, invisibly, when its configuration is valid.
#' @export
#' @examples
#' check_component(quality_rule("nonnegative", ~ amount >= 0))
check_component <- function(x, ...) UseMethod("check_component")
#' @export
check_component.default <- function(x, ...) {
  abort("This component needs a check_component() preflight method.")
}
#' @export
check_component.NULL <- function(x, ...) invisible(x)
#' @export
check_component.data.frame <- function(x, ...) {
  if (anyDuplicated(names(x)) || anyNA(names(x)) || any(!nzchar(names(x)))) {
    abort("Source column names must be non-empty and unique.")
  }
  invisible(x)
}
#' @export
check_component.function <- function(x, ...) invisible(x)
#' @export
check_component.tw_source <- function(x, ...) {
  if (!is.function(x$reader)) {
    abort("The file source needs a reader function.")
  }
  if (!file.exists(x$path) || dir.exists(x$path)) {
    abort("Source file is missing.", "tw_missing_delivery")
  }
  if (identical(x$reader, excel_reader)) {
    need("readxl")
  }
  invisible(x)
}
#' @export
check_component.tw_database_source <- function(x, ...) {
  if (!is.function(x$connection) && !DBI::dbIsValid(x$connection)) {
    abort(
      "The source connection is closed. Open it or supply a connection factory."
    )
  }
  invisible(x)
}
#' @export
check_component.tw_sql_transform <- function(x, ...) {
  scalar(x$query, "query")
  need("duckdb")
  invisible(x)
}
#' @export
check_component.tw_rule <- function(x, ...) {
  scalar(x$name, "rule name")
  if (identical(x$engine, "pointblank")) {
    need("pointblank")
  }
  if (!is.function(x$check) && !inherits(x$check, "formula")) {
    abort("The quality rule needs a function or formula.")
  }
  if (inherits(x$check, "formula") && length(x$check) != 2L) {
    abort("Use a one-sided quality formula, for example ~ amount >= 0.")
  }
  invisible(x)
}

component_method <- function(generic, x) {
  any(vapply(
    class(x),
    function(cl) {
      !is.null(utils::getS3method(generic, cl, optional = TRUE))
    },
    logical(1)
  ))
}

assert_component <- function(x, generic) {
  if (!component_method(generic, x)) {
    abort(paste0(
      "Component class `",
      class(x)[[1]],
      "` needs a ",
      generic,
      "() method."
    ))
  }
  check_component(x)
  invisible(x)
}

frame_result <- function(data, label) {
  if (!is.data.frame(data)) {
    abort(
      paste0(
        label,
        " did not return a data frame or tibble. Received: ",
        paste(class(data), collapse = "/"),
        "."
      ),
      "tw_component_result"
    )
  }
  check_component.data.frame(data)
  data
}


is_lazy_table <- function(x) {
  inherits(
    x,
    c("tbl_sql", "Table", "RecordBatch", "Dataset", "arrow_dplyr_query")
  )
}

table_result <- function(data, label) {
  if (!is.data.frame(data) && !is_lazy_table(data)) {
    abort(
      paste0(
        label,
        " did not return a data frame or lazy table. Received: ",
        paste(class(data), collapse = "/"),
        ". Combine multiple sources in a transformation before validation."
      ),
      "tw_component_result"
    )
  }
  columns <- if (is_lazy_table(data)) {
    colnames(data) %||% names(data)
  } else {
    names(data)
  }
  if (anyDuplicated(columns) || anyNA(columns) || any(!nzchar(columns))) {
    abort(paste0(label, " must have unique, non-empty column names."))
  }
  data
}

#' @export
read_source.tbl_sql <- function(source, ...) source
#' @export
check_component.tbl_sql <- function(x, ...) {
  if (!DBI::dbIsValid(dbplyr::remote_con(x))) {
    abort("The lazy table connection is closed. Open it before running.")
  }
  invisible(table_result(x, "The source"))
}
#' @export
inspect.tbl_sql <- function(x, ...) {
  list(
    type = "lazy database table",
    columns = colnames(x),
    query = as.character(dbplyr::sql_render(x))
  )
}
#' @export
read_source.tw_product <- function(source, ...) result_data(run(source, ...))
#' @export
check_component.tw_product <- function(x, ...) invisible(validate(x))

#' Read a pinned lake release as a product source
#'
#' Execution resolves an omitted `release_id` once and records its immutable
#' identity. Pass a configuration to open an existing lake read-only, collect
#' the selected release into an ordinary tibble, and close the owned connection.
#' This requires enough memory for the release. A connected lake instead returns
#' a lazy table and remains caller-owned; keep it open while using that table.
#' Construction and validation do not open or create a lake. This source connects
#' governed releases to ordinary product composition and consumer exports.
#' When publishing back to the same lake, execution can reuse its open handle;
#' configuration sources still return materialized values without owning it.
#' @param lake Connected lake or [lake_config()] describing an existing lake.
#' @param asset Published asset name.
#' @param release_id Optional immutable release identifier.
#' @returns A source adapter. Reads return a lazy table for a connected lake or
#'   a tibble for a configuration, with the exact release reference attached.
#' @export
#' @examples
#' if (FALSE) {
#'   product("summary") |>
#'     add_source(source_release(lake, "orders")) |>
#'     add_transform(function(data) dplyr::summarise(data, rows = dplyr::n())) |>
#'     run()
#' }
source_release <- function(lake, asset, release_id = NULL) {
  asset_id(asset)
  if (!is.null(release_id)) {
    scalar(release_id, "release_id")
  }
  source <- structure(
    list(lake = lake, asset = asset, release_id = release_id),
    class = "tw_release_source"
  )
  check_component(source)
  source
}
#' @export
check_component.tw_release_source <- function(x, ...) {
  asset_id(x$asset)
  if (!is.null(x$release_id)) {
    scalar(x$release_id, "release_id")
  }
  if (inherits(x$lake, "tw_config")) {
    do.call(lake_config, unclass(x$lake))
    need("duckdb")
  } else if (inherits(x$lake, "tw_lake")) {
    assert_lake(x$lake)
  } else {
    abort("Use a connected lake or lake_config() for a release source.")
  }
  invisible(x)
}
#' @export
inspect.tw_release_source <- function(x, ...) {
  config <- if (inherits(x$lake, "tw_config")) x$lake else x$lake$config
  list(
    type = "lake release",
    asset = x$asset,
    release_id = x$release_id,
    backend = config$backend
  )
}
#' @export
read_source.tw_release_source <- function(source, ...) {
  read_release_source(source)
}

read_release_source <- function(source, execution_lake = NULL) {
  check_component(source)
  materialized <- inherits(source$lake, "tw_config")
  if (
    materialized &&
      inherits(source$output_lake, "tw_lake") &&
      DBI::dbIsValid(source$output_lake$con)
  ) {
    execution_lake <- source$output_lake
  }
  reuse <- materialized &&
    inherits(execution_lake, "tw_lake") &&
    DBI::dbIsValid(execution_lake$con) &&
    identical(
      source$lake[c("backend", "catalog", "storage")],
      execution_lake$config[c("backend", "catalog", "storage")]
    )
  owned <- materialized && !reuse
  lake <- if (reuse) {
    execution_lake
  } else if (owned) {
    connect_lake(source$lake, read_only = TRUE)
  } else {
    source$lake
  }
  if (owned) {
    on.exit(disconnect_lake(lake), add = TRUE)
  }
  ref <- resolve_release(lake, source$asset, source$release_id)
  data <- dplyr::tbl(
    lake$con,
    table_id(ref$schema_name[[1]], ref$table_name[[1]])
  )
  if (materialized) {
    data <- collect(data)
  }
  attr(data, "tw_input_reference") <- list(
    asset = source$asset,
    release_id = ref$release_id[[1]],
    hash = ref$input_hash[[1]],
    run_id = source$run_id %||% NULL
  )
  data
}
