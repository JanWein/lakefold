#' Read a source using an interchangeable adapter
#'
#' Data frames and zero-argument functions work directly. File paths are
#' normalized by [dl_add_source()]. A source method returns a data frame or
#' tibble. Use a function to call an API or another existing client.
#' @param source Source object, data frame or zero-argument function.
#' @param ... Adapter-specific options.
#' @returns A data frame or tibble. Connections supplied by callers stay open.
#' @export
#' @examples
#' dl_read_source(function() data.frame(id = 1:2))
dl_read_source <- function(source, ...) UseMethod("dl_read_source")
#' @export
dl_read_source.data.frame <- function(source, ...) source
#' @export
dl_read_source.function <- function(source, ...) source()
#' @export
dl_read_source.dl_source <- function(source, ...) source$reader(source$path)
#' @export
dl_read_source.default <- function(source, ...) {
  abort(
    "This source needs a dl_read_source() method. You can also pass a function returning a data frame."
  )
}

#' Describe a DBI table or SQL query as a source
#'
#' Supply exactly one of `table` and `query`. The connection may be an open DBI
#' connection or a zero-argument factory. Only factory-created connections are
#' closed by lakefold. SQL is passed to DBI unchanged; use `params` for values.
#' Nothing is queried during construction or structural preflight.
#' @param connection DBI connection or function opening one.
#' @param table Table name or [DBI::Id()].
#' @param query A single SQL query string.
#' @param params Parameters passed to [DBI::dbGetQuery()].
#' @returns A source specification accepted by [dl_add_source()].
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' con <- DBI::dbConnect(duckdb::duckdb())
#' DBI::dbWriteTable(con, "orders", data.frame(id = 1:2))
#' dl_read_source(dl_source_database(con, table = "orders"))
#' DBI::dbDisconnect(con, shutdown = TRUE)
dl_source_database <- function(
  connection,
  table = NULL,
  query = NULL,
  params = NULL
) {
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
      params = params
    ),
    class = "dl_database_source"
  )
}
#' @export
dl_read_source.dl_database_source <- function(source, ...) {
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
#' Ordinary functions receive and return a data frame or tibble in composed
#' products. Extension methods may delegate to existing tools. They must return
#' a data frame or tibble. No transformation class is required for R functions.
#' @param transform Function or adapter object.
#' @param data Input data frame.
#' @param ... Adapter-specific options.
#' @returns A data frame or tibble.
#' @export
#' @examples
#' dl_execute_transform(function(data) transform(data, doubled = amount * 2),
#'   data.frame(amount = 10))
dl_execute_transform <- function(transform, data, ...) {
  UseMethod("dl_execute_transform")
}
#' @export
dl_execute_transform.function <- function(transform, data, ...) transform(data)
#' @export
dl_execute_transform.default <- function(transform, data, ...) {
  abort(
    "This transformation needs a dl_execute_transform() method. An ordinary R function also works."
  )
}

#' Apply a DuckDB SQL query to a data frame
#'
#' The input is available as `data` in a private, temporary DuckDB connection.
#' SQL is executed unchanged by DuckDB and must return a table. This adapter is
#' intended for trusted analytical queries; it does not sandbox SQL.
#' @param query SQL query referencing the input table `data`.
#' @returns A transformation accepted by [dl_add_transform()].
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' dl_product("totals") |>
#'   dl_add_source(data.frame(amount = c(10, 20))) |>
#'   dl_add_transform(dl_sql("SELECT sum(amount) AS total FROM data")) |>
#'   dl_run() |>
#'   dl_collect()
dl_sql <- function(query) {
  structure(list(query = scalar(query, "query")), class = "dl_sql_transform")
}
#' @export
dl_execute_transform.dl_sql_transform <- function(transform, data, ...) {
  need("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
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
#' dl_check_component(dl_rule("nonnegative", ~ amount >= 0))
dl_check_component <- function(x, ...) UseMethod("dl_check_component")
#' @export
dl_check_component.default <- function(x, ...) {
  abort("This component needs a dl_check_component() preflight method.")
}
#' @export
dl_check_component.NULL <- function(x, ...) invisible(x)
#' @export
dl_check_component.data.frame <- function(x, ...) {
  if (anyDuplicated(names(x)) || anyNA(names(x)) || any(!nzchar(names(x)))) {
    abort("Source column names must be non-empty and unique.")
  }
  invisible(x)
}
#' @export
dl_check_component.function <- function(x, ...) invisible(x)
#' @export
dl_check_component.dl_source <- function(x, ...) {
  if (!is.function(x$reader)) {
    abort("The file source needs a reader function.")
  }
  if (!file.exists(x$path) || dir.exists(x$path)) {
    abort("Source file is missing.", "dl_missing_delivery")
  }
  if (identical(x$reader, excel_reader)) {
    need("readxl")
  }
  invisible(x)
}
#' @export
dl_check_component.dl_database_source <- function(x, ...) {
  if (!is.function(x$connection) && !DBI::dbIsValid(x$connection)) {
    abort(
      "The source connection is closed. Open it or supply a connection factory."
    )
  }
  invisible(x)
}
#' @export
dl_check_component.dl_sql_transform <- function(x, ...) {
  scalar(x$query, "query")
  need("duckdb")
  invisible(x)
}
#' @export
dl_check_component.dl_rule <- function(x, ...) {
  scalar(x$name, "rule name")
  if (identical(x$engine, "pointblank")) {
    need("pointblank")
  }
  if (!is.function(x$check) && !inherits(x$check, "formula")) {
    abort("The quality rule needs a function or formula.")
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
  dl_check_component(x)
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
      "dl_component_result"
    )
  }
  dl_check_component.data.frame(data)
  data
}
