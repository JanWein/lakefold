#' Define metadata and storage configuration
#' @param path Local path.
#' @param connection_env Environment variable containing a PostgreSQL libpq
#'   string.
#' @param bucket S3 bucket.
#' @param prefix Prefix within the bucket.
#' @param endpoint S3 endpoint, including https://.
#' @param region AWS region.
#' @return A serializable configuration object containing no credentials.
#' @export
#' @examples
#' registry_duckdb(file.path(tempdir(), "lake.db"))
#' storage_local(file.path(tempdir(), "data"))
#' registry_postgres("DUCKLAKE_PG_CONNECTION")
registry_duckdb <- function(path) {
  structure(
    list(type = "duckdb", path = absolute_path(path)),
    class = "tw_catalog_spec"
  )
}
#' @rdname registry_duckdb
#' @export
registry_postgres <- function(connection_env = "DUCKLAKE_PG_CONNECTION") {
  structure(
    list(
      type = "postgres",
      connection_env = scalar(connection_env, "connection_env")
    ),
    class = "tw_catalog_spec"
  )
}
#' @rdname registry_duckdb
#' @export
storage_local <- function(path) {
  structure(
    list(type = "local", path = absolute_path(path)),
    class = "tw_storage_spec"
  )
}
#' @rdname registry_duckdb
#' @export
storage_s3 <- function(
  bucket,
  prefix = "dataloom/",
  endpoint,
  region = "eu-central-1"
) {
  scalar(bucket, "bucket")
  scalar(endpoint, "endpoint")
  if (!grepl("^https?://[^/]+/?$", endpoint)) {
    abort("endpoint must contain a scheme and host, without a path.")
  }
  prefix <- gsub("^/+|/+$", "", prefix)
  structure(
    list(
      type = "s3",
      bucket = bucket,
      prefix = prefix,
      endpoint = sub("/$", "", endpoint),
      region = region
    ),
    class = "tw_storage_spec"
  )
}

#' Set up or reconnect to a data lake
#' @param catalog Metadata configuration.
#' @param storage Data file storage configuration.
#' @param layers Schema names.
#' @param landing Local immutable landing directory (also used as staging for
#'   S3).
#' @param backend DuckLake, or local DuckDB for offline development.
#' @param install_extensions Allow DuckDB to install required extensions.
#' @param read_only Attach existing storage read-only and skip schema creation
#'   and migration. A lake created by a newer package may require an upgrade.
#' @param config A configuration from a previously connected lake.
#' @return A connected lake handle. Close it with disconnect_lake().
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' lake
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
setup_lake <- function(
  catalog = registry_duckdb("metadata.ducklake"),
  storage = storage_local("data"),
  layers = c("raw", "validated", "products"),
  landing = "landing",
  backend = c("ducklake", "duckdb"),
  install_extensions = TRUE,
  read_only = FALSE
) {
  connect_lake(lake_config(
    catalog,
    storage,
    layers,
    landing,
    backend,
    install_extensions,
    read_only
  ))
}

#' Define a lake without opening a connection
#'
#' This constructor validates configuration and resolves paths, but does not
#' create directories, install extensions, connect to databases or read secrets.
#' Pass its result to [connect_lake()] or [target_lake()] when ready to execute.
#' @inheritParams setup_lake
#' @return A connection-free `lake_config` specification.
#' @export
#' @examples
#' config <- lake_config(backend = "duckdb")
#' print(config)
lake_config <- function(
  catalog = registry_duckdb("metadata.ducklake"),
  storage = storage_local("data"),
  layers = c("raw", "validated", "products"),
  landing = "landing",
  backend = c("ducklake", "duckdb"),
  install_extensions = TRUE,
  read_only = FALSE
) {
  flag(read_only, "read_only")
  backend <- match.arg(backend)
  if (
    !inherits(catalog, "tw_catalog_spec") ||
      !inherits(storage, "tw_storage_spec")
  ) {
    abort("Use catalog and storage constructors.")
  }
  invisible(lapply(layers, ident))
  if (length(layers) == 0L || anyDuplicated(layers)) {
    abort("layers must be non-empty and unique.")
  }
  if (
    backend == "duckdb" && (catalog$type != "duckdb" || storage$type != "local")
  ) {
    abort("The DuckDB backend only supports local storage and catalog.")
  }
  structure(
    list(
      catalog = catalog,
      storage = storage,
      layers = layers,
      landing = absolute_path(landing),
      backend = backend,
      install_extensions = install_extensions,
      read_only = read_only
    ),
    class = "tw_config"
  )
}

#' @rdname setup_lake
#' @export
connect_lake <- function(config, read_only = config$read_only %||% FALSE) {
  need("duckdb")
  if (!inherits(config, "tw_config")) {
    abort("Use lake_config() to describe this lake.")
  }
  flag(read_only, "read_only")
  config$read_only <- read_only
  if (
    read_only &&
      config$catalog$type == "duckdb" &&
      !file.exists(config$catalog$path)
  ) {
    abort("A read-only catalog must already exist.")
  }
  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = ":memory:",
    bigint = "integer64"
  )
  ok <- FALSE
  on.exit(if (!ok) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  lake <- structure(list(con = con, config = config), class = "tw_lake")
  cat <- config$catalog
  st <- config$storage
  if (!read_only) {
    dir.create(config$landing, recursive = TRUE, showWarnings = FALSE)
    if (cat$type == "duckdb") {
      dir.create(dirname(cat$path), recursive = TRUE, showWarnings = FALSE)
    }
    if (st$type == "local") {
      dir.create(st$path, recursive = TRUE, showWarnings = FALSE)
    }
  }
  if (config$backend == "duckdb") {
    exec(
      lake,
      paste(
        "ATTACH",
        qlit(lake, cat$path),
        "AS lake",
        if (read_only) "(READ_ONLY)" else ""
      )
    )
  } else {
    extensions <- c(
      "ducklake",
      if (cat$type == "postgres") "postgres",
      if (st$type == "s3") "httpfs"
    )
    for (ext in extensions) {
      if (isTRUE(config$install_extensions)) {
        exec(lake, paste("INSTALL", ext))
      }
      exec(lake, paste("LOAD", ext))
    }
    if (st$type == "s3") {
      # Resolve credentials at execution time and never save them to the registry.
      key <- Sys.getenv("AWS_ACCESS_KEY_ID")
      secret <- Sys.getenv("AWS_SECRET_ACCESS_KEY")
      if (!nzchar(key) || !nzchar(secret)) {
        abort("Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.")
      }
      parts <- c(
        "TYPE S3",
        paste("KEY_ID", qlit(lake, key)),
        paste("SECRET", qlit(lake, secret)),
        paste("REGION", qlit(lake, st$region)),
        paste("ENDPOINT", qlit(lake, sub("^https?://", "", st$endpoint))),
        "URL_STYLE 'path'",
        paste(
          "USE_SSL",
          if (startsWith(st$endpoint, "https://")) "true" else "false"
        ),
        paste("SCOPE", qlit(lake, paste0("s3://", st$bucket, "/")))
      )
      token <- Sys.getenv("AWS_SESSION_TOKEN")
      if (nzchar(token)) {
        parts <- c(parts, paste("SESSION_TOKEN", qlit(lake, token)))
      }
      tryCatch(
        exec(
          lake,
          paste0("CREATE SECRET tw_s3 (", paste(parts, collapse = ", "), ")")
        ),
        error = function(e) {
          abort(
            "S3 credential configuration failed; check endpoint and environment variables."
          )
        }
      )
      data_path <- paste0(
        "s3://",
        st$bucket,
        "/",
        if (nzchar(st$prefix)) paste0(st$prefix, "/"),
        "tables/"
      )
    } else {
      data_path <- paste0(st$path, "/")
    }
    uri <- if (cat$type == "postgres") {
      value <- Sys.getenv(cat$connection_env)
      if (!nzchar(value)) {
        abort(paste("Set", cat$connection_env))
      }
      paste0("ducklake:postgres:", value)
    } else {
      paste0("ducklake:", cat$path)
    }
    tryCatch(
      exec(
        lake,
        paste(
          "ATTACH",
          qlit(lake, uri),
          "AS lake (DATA_PATH",
          qlit(lake, data_path),
          if (read_only) ", READ_ONLY)" else ")"
        )
      ),
      error = function(e) {
        abort(
          "DuckLake attach failed. Check extension, catalog connectivity and storage access. Credentials are omitted."
        )
      }
    )
  }
  if (!read_only) {
    for (s in c(config$layers, "_dl")) {
      exec(
        lake,
        paste(
          "CREATE SCHEMA IF NOT EXISTS",
          paste(qident(lake, c("lake", s)), collapse = ".")
        )
      )
    }
    registry_init(lake)
  } else {
    versions <- tryCatch(
      registry(lake, "schema_version")$version,
      error = function(e) {
        abort("Registry is missing. Open with a writable connection first.")
      }
    )
    if (!length(versions) || anyNA(versions) || max(versions) != 3L) {
      abort(
        "Unsupported registry version. Open with a compatible writable package first."
      )
    }
  }
  query(lake, "SELECT 1 AS connection_test")
  ok <- TRUE
  lake
}

#' Close a lake connection
#' @param lake Connected lake.
#' @return Invisibly TRUE.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
disconnect_lake <- function(lake) {
  if (DBI::dbIsValid(lake$con)) {
    DBI::dbDisconnect(lake$con, shutdown = TRUE)
  }
  invisible(TRUE)
}
#' @export
print.tw_lake <- function(x, ...) {
  cat(
    "<tidyweave>",
    x$config$backend,
    "| layers:",
    paste(x$config$layers, collapse = ", "),
    "\n"
  )
  invisible(x)
}
