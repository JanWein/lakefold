`%||%` <- function(x, y) if (is.null(x)) y else x
abort <- function(message, class = "dl_error", ...) {
  rlang::abort(message, class = class, ...)
}
need <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    abort(paste("Install optional package:", package))
  }
}
scalar <- function(x, what) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    abort(paste(what, "must be a non-empty string."))
  }
  x
}
absolute_path <- function(path) {
  path <- path.expand(scalar(path, "path"))
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) {
    path <- file.path(getwd(), path)
  }
  normalizePath(path, winslash = "/", mustWork = FALSE)
}
ident <- function(x) {
  scalar(x, "Identifier")
  if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", x)) {
    abort(paste("Invalid identifier:", x))
  }
  x
}
column_name <- function(x) scalar(x, "Column name")
assert_writable <- function(lake) {
  assert_lake(lake)
  if (isTRUE(lake$config$read_only)) {
    abort(
      "This lake is read-only. Open a writable connection for this operation.",
      "dl_read_only"
    )
  }
}
asset_id <- function(x) {
  scalar(x, "Asset id")
  if (!grepl("^[A-Za-z][A-Za-z0-9_.]*$", x)) {
    abort("Asset ids must use letters, digits, underscores or dots.")
  }
  x
}
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")
uid <- function() {
  paste0(
    "r",
    substr(
      digest::digest(
        list(now(), Sys.getpid(), tempfile("lakefold-id-")),
        algo = "sha256"
      ),
      1,
      24
    )
  )
}
canonical <- function(x) {
  if (is.function(x)) {
    return(list(
      formals = paste(deparse(formals(x)), collapse = "\n"),
      body = paste(deparse(body(x)), collapse = "\n")
    ))
  }
  if (rlang::is_quosure(x)) {
    return(list(
      expression = paste(
        deparse(rlang::get_expr(x), width.cutoff = 500L),
        collapse = "\n"
      ),
      format = 2L
    ))
  }
  if (is.list(x)) {
    return(lapply(x, canonical))
  }
  x
}
jencode <- function(x) {
  as.character(jsonlite::toJSON(
    canonical(x),
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA
  ))
}
jdecode <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)
fingerprint <- function(x) {
  digest::digest(jencode(x), algo = "sha256", serialize = FALSE)
}
qident <- function(lake, x) as.character(DBI::dbQuoteIdentifier(lake$con, x))
qlit <- function(lake, x) as.character(DBI::dbQuoteLiteral(lake$con, x))
table_sql <- function(lake, schema, name) {
  paste(qident(lake, c("lake", schema, name)), collapse = ".")
}
table_id <- function(schema, name) {
  DBI::Id(catalog = "lake", schema = schema, table = name)
}
exec <- function(lake, sql, params = NULL) {
  if (is.null(params)) {
    DBI::dbExecute(lake$con, sql)
  } else {
    DBI::dbExecute(lake$con, sql, params = params)
  }
}
query <- function(lake, sql, params = NULL) {
  tibble::as_tibble(
    if (is.null(params)) {
      DBI::dbGetQuery(lake$con, sql)
    } else {
      DBI::dbGetQuery(lake$con, sql, params = params)
    }
  )
}
meta <- function(lake, name) table_sql(lake, "_dl", name)
insert_meta <- function(lake, name, values) {
  assert_writable(lake)
  cols <- paste(qident(lake, names(values)), collapse = ", ")
  marks <- paste(rep("?", length(values)), collapse = ", ")
  exec(
    lake,
    paste0(
      "INSERT INTO ",
      meta(lake, name),
      " (",
      cols,
      ") VALUES (",
      marks,
      ")"
    ),
    unname(values)
  )
}
assert_lake <- function(lake) {
  if (!inherits(lake, "dl_lake") || !DBI::dbIsValid(lake$con)) {
    abort("A connected dl_lake is required.")
  }
}
count_rows <- function(x) {
  as.numeric(dplyr::collect(dplyr::summarise(x, n = dplyr::n()))$n[[1]])
}
materialize <- function(lake, data, schema, name) {
  dest <- table_sql(lake, schema, name)
  if (inherits(data, "tbl_sql")) {
    exec(lake, paste0("CREATE TABLE ", dest, " AS ", dbplyr::sql_render(data)))
  } else if (is.data.frame(data)) {
    tmp <- uid()
    duckdb::duckdb_register(lake$con, tmp, as.data.frame(data))
    on.exit(duckdb::duckdb_unregister(lake$con, tmp), add = TRUE)
    exec(
      lake,
      paste0("CREATE TABLE ", dest, " AS SELECT * FROM ", qident(lake, tmp))
    )
  } else {
    abort("Readers and builders must return a data.frame or a lazy SQL table.")
  }
  dplyr::tbl(lake$con, table_id(schema, name))
}


null_counts <- function(data, columns) {
  if (!length(columns)) {
    return(setNames(numeric(), character()))
  }
  if (!inherits(data, "tbl_sql")) {
    return(vapply(data[columns], function(x) sum(is.na(x)), numeric(1)))
  }
  expressions <- setNames(
    lapply(columns, function(column) {
      rlang::expr(sum(as.integer(is.na(!!rlang::sym(column))), na.rm = TRUE))
    }),
    columns
  )
  result <- dplyr::collect(dplyr::summarise(data, !!!expressions))
  setNames(as.numeric(result[1, ]), columns)
}
