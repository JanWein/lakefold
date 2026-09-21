#' Define metadata and storage configuration
#' @param path Local path.
#' @param connection_env Environment variable containing a PostgreSQL libpq
#'   string.
#' @param lock_timeout Seconds to wait for another PostgreSQL writer. Writes are
#'   coordinated per catalog database using optional RPostgres. All writers must
#'   use this protocol; direct SQL and older clients are not coordinated.
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
registry_postgres <- function(
  connection_env = "DUCKLAKE_PG_CONNECTION",
  lock_timeout = 30
) {
  if (
    !is.numeric(lock_timeout) ||
      length(lock_timeout) != 1L ||
      !is.finite(lock_timeout) ||
      lock_timeout < 0
  ) {
    abort("lock_timeout must be a non-negative number of seconds.")
  }
  structure(
    list(
      type = "postgres",
      lock_timeout = lock_timeout,
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
#' @param path Optional self-contained local folder, as in [open_lake()].
#'   Supply this instead of `catalog`, `storage` and `landing`. New folders
#'   default to DuckDB; use `backend = "ducklake"` for DuckLake. Saved settings
#'   are reused when reopening.
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
  read_only = FALSE,
  path = NULL
) {
  if (!is.null(path)) {
    if (!missing(catalog) || !missing(storage) || !missing(landing)) {
      abort(
        "Supply path or explicit catalog, storage and landing settings, not both."
      )
    }
    args <- list(
      path = path,
      install_extensions = install_extensions,
      read_only = read_only
    )
    if (!missing(backend)) {
      args$backend <- backend
    }
    if (!missing(layers)) {
      args$layers <- layers
    }
    return(connect_lake(do.call(lake_config, args)))
  }
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
#' With `path`, it may read an existing `tidyweave.json` to preserve the saved
#' backend and ordered layers, including named layer roles. It never creates
#' or writes files. A new shorthand lake defaults to
#' DuckDB; other calls retain the usual DuckLake default. The local layout and
#' backend marker are shared with [open_lake()]. Unknown non-empty folders are
#' refused rather than interpreted as a new lake.
#' Pass its result to [connect_lake()] or [target_lake()] when ready to execute.
#' @inheritParams setup_lake
#' @param path Optional local lake folder. Derives `metadata.duckdb`, `data`
#'   and `landing` within that folder. Supply either `path` or explicit
#'   `catalog`, `storage` and `landing`, not both. An explicit backend must
#'   agree with a folder's saved backend. Explicit layers must match its saved
#'   layers; omit them when reopening. Default layers are unchanged;
#'   select `layers = c("raw", "staging", "core", "marts")` when needed.
#' @return A connection-free `lake_config` specification.
#' @export
#' @examples
#' config <- lake_config(backend = "duckdb")
#' print(config)
#' local <- lake_config(path = file.path(tempdir(), "my-data-lake"))
#' print(local)
lake_config <- function(
  catalog = registry_duckdb("metadata.ducklake"),
  storage = storage_local("data"),
  layers = c("raw", "validated", "products"),
  landing = "landing",
  backend = c("ducklake", "duckdb"),
  install_extensions = TRUE,
  read_only = FALSE,
  path = NULL
) {
  layers_missing <- missing(layers)
  flag(read_only, "read_only")
  if (!is.null(path)) {
    if (!missing(catalog) || !missing(storage) || !missing(landing)) {
      abort(
        "Supply path or explicit catalog, storage and landing settings, not both."
      )
    }
    path <- absolute_path(path)
    local <- local_lake_settings(
      path,
      if (missing(backend)) NULL else match.arg(backend),
      if (missing(layers)) NULL else layers
    )
    backend <- local$backend
    layers <- local$layers
    catalog <- registry_duckdb(file.path(path, "metadata.duckdb"))
    storage <- storage_local(file.path(path, "data"))
    landing <- file.path(path, "landing")
  } else {
    backend <- match.arg(backend)
  }
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
  out <- structure(
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
  if (!is.null(path)) {
    attr(out, "tw_local_path") <- path
    attr(out, "tw_legacy_layers") <- isTRUE(local$legacy) && layers_missing
  }
  out
}

local_lake_settings <- function(path, backend = NULL, layers = NULL) {
  if (file.exists(path) && !dir.exists(path)) {
    abort("The local lake path is a file. Choose a folder.")
  }
  manifest <- file.path(path, "tidyweave.json")
  if (file.exists(manifest)) {
    saved <- tryCatch(
      jdecode(paste(readLines(manifest, warn = FALSE), collapse = "\n")),
      error = function(e) NULL
    )
    if (
      !is.list(saved) ||
        !(identical(saved$format, 1L) || identical(saved$format, 2L)) ||
        !is.character(saved$backend) ||
        length(saved$backend) != 1L ||
        is.na(saved$backend) ||
        !saved$backend %in% c("duckdb", "ducklake")
    ) {
      abort(
        "Invalid tidyweave.json. Restore the folder's original configuration."
      )
    }
    if (!is.null(backend) && !identical(backend, saved$backend)) {
      abort(
        "This folder uses a different backend. Reopen without backend or choose a new folder."
      )
    }
    if (identical(saved$format, 2L)) {
      valid <- function(x) {
        is.list(x) &&
          length(x) > 0L &&
          all(vapply(
            x,
            function(value) {
              is.character(value) && length(value) == 1L && !is.na(value)
            },
            logical(1)
          ))
      }
      if (!valid(saved$layers)) {
        abort(
          "Invalid tidyweave.json layers. Restore the folder's original configuration."
        )
      }
      saved_layers <- unlist(saved$layers, use.names = FALSE)
      if (
        anyDuplicated(saved_layers) ||
          any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", saved_layers))
      ) {
        abort(
          "Invalid tidyweave.json layers. Restore the folder's original configuration."
        )
      }
      if (!is.null(saved$layer_names)) {
        if (
          !valid(saved$layer_names) ||
            length(saved$layer_names) != length(saved_layers)
        ) {
          abort(
            "Invalid tidyweave.json layer names. Restore the folder's original configuration."
          )
        }
        names(saved_layers) <- unlist(saved$layer_names, use.names = FALSE)
      }
      if (!is.null(layers) && !identical(layers, saved_layers)) {
        abort(
          "This folder has different saved layers. Omit layers to reuse its configuration, or choose a new folder."
        )
      }
      layers <- saved_layers
    }
    return(list(
      backend = saved$backend,
      layers = layers %||% c("raw", "validated", "products"),
      legacy = identical(saved$format, 1L)
    ))
  }
  if (
    dir.exists(path) &&
      length(list.files(path, all.files = TRUE, no.. = TRUE))
  ) {
    abort(
      "This folder is not empty and has no tidyweave.json. Use its original lake_config() or choose an empty folder."
    )
  }
  list(
    backend = backend %||% "duckdb",
    layers = layers %||% c("raw", "validated", "products"),
    legacy = FALSE
  )
}

save_local_lake_settings <- function(config, upgrade = FALSE) {
  path <- attr(config, "tw_local_path")
  if (is.null(path)) {
    return(invisible(NULL))
  }
  manifest <- file.path(path, "tidyweave.json")
  if (file.exists(manifest)) {
    settings <- local_lake_settings(path, config$backend, config$layers)
    if (!upgrade || !isTRUE(settings$legacy)) return(invisible(NULL))
  }
  temporary <- tempfile(".local-config-", tmpdir = path)
  on.exit(unlink(temporary), add = TRUE)
  writeLines(
    jencode(list(
      format = 2L,
      backend = config$backend,
      layers = unname(as.list(config$layers)),
      layer_names = if (is.null(names(config$layers))) {
        NULL
      } else {
        as.list(names(config$layers))
      }
    )),
    temporary
  )
  if (!suppressWarnings(file.rename(temporary, manifest))) {
    abort("Unable to save tidyweave.json for the local lake.")
  }
  invisible(NULL)
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
  local_path <- attr(config, "tw_local_path")
  if (!is.null(local_path)) {
    local <- local_lake_settings(local_path, config$backend, config$layers)
    attr(config, "tw_legacy_layers") <- isTRUE(local$legacy) &&
      isTRUE(attr(config, "tw_legacy_layers"))
  }
  if (
    read_only &&
      config$catalog$type == "duckdb" &&
      !file.exists(config$catalog$path)
  ) {
    abort("A read-only catalog must already exist.")
  }
  if (!is.null(local_path) && !read_only) {
    dir.create(local_path, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(local_path)) {
      abort("Unable to create the local lake folder.")
    }
    save_local_lake_settings(config)
  }
  con <- DBI::dbConnect(
    suppressMessages(duckdb::duckdb()),
    dbdir = ":memory:",
    bigint = "integer64"
  )
  ok <- FALSE
  on.exit(if (!ok) DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  lake <- structure(
    list(
      con = con,
      config = config,
      writer_state = lake_writer_state(config)
    ),
    class = "tw_lake"
  )
  if (!read_only) {
    assert_writable(lake)
  }
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
  if (isTRUE(attr(config, "tw_legacy_layers"))) {
    existing_layers <- query(
      lake,
      "SELECT schema_name FROM information_schema.schemata WHERE catalog_name = 'lake' ORDER BY schema_name"
    )$schema_name
    custom <- setdiff(existing_layers, c("main", "_dl", config$layers))
    if (length(custom)) {
      abort(paste0(
        "This older folder did not save its layer configuration. Reopen once with layers = c(",
        paste(
          encodeString(setdiff(existing_layers, c("main", "_dl")), quote = '"'),
          collapse = ", "
        ),
        ") in your intended order. A writable open will remember this choice."
      ))
    }
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
    if (!length(versions) || anyNA(versions) || max(versions) != 4L) {
      abort(
        "Unsupported registry version. Open with a compatible writable package first."
      )
    }
  }
  query(lake, "SELECT 1 AS connection_test")
  if (!read_only) {
    save_local_lake_settings(config, upgrade = TRUE)
  }
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
