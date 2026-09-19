#' Open a local lake with sensible defaults
#'
#' Creates or reopens a self-contained local folder. DuckDB is the default and
#' needs no extension download or external service. The backend is remembered
#' in `lakefold.json`; reopening a folder never silently switches backends.
#' A new lake needs an empty or nonexistent folder. Existing lakes made with
#' custom configuration still open through [dl_connect()].
#' Use [dl_config()] and [dl_connect()] for custom layers or remote storage.
#' @param path Local folder, created if needed. Defaults to `"lakefold"` in
#'   the working directory.
#' @param backend Optional `"duckdb"` or `"ducklake"`. DuckLake requires its
#'   DuckDB extension. Defaults to the saved choice, or DuckDB for a new folder.
#' @param lake Connected lake to close.
#' @returns `dl_open()` returns a connected `dl_lake`. `dl_close()` invisibly
#'   returns `TRUE`; it is an alias for [dl_disconnect()].
#' @seealso [dl_write()], [dl_read()]
#' @export
#' @examples
#' root <- tempfile("lakefold-")
#' lake <- dl_open(root)
#' dl_write(lake, data.frame(id = 1:2), "orders")
#' dl_read(lake, "orders")
#' dl_close(lake)
#' lake <- dl_open(root) # reopens the same data
#' dl_read(lake, "orders")
#' dl_close(lake)
#' unlink(root, recursive = TRUE)
dl_open <- function(path = "lakefold", backend = NULL) {
  path <- absolute_path(path)
  if (!is.null(backend)) {
    backend <- match.arg(backend, c("duckdb", "ducklake"))
  }
  manifest <- file.path(path, "lakefold.json")
  if (file.exists(manifest)) {
    saved <- tryCatch(
      jdecode(paste(readLines(manifest, warn = FALSE), collapse = "\n")),
      error = function(e) NULL
    )
    if (
      !is.list(saved) ||
        !identical(saved$format, 1L) ||
        !is.character(saved$backend) ||
        length(saved$backend) != 1L ||
        !saved$backend %in% c("duckdb", "ducklake")
    ) {
      abort(
        "Invalid lakefold.json. Restore the folder's original configuration."
      )
    }
    if (!is.null(backend) && !identical(backend, saved$backend)) {
      abort(
        "This folder uses a different backend. Reopen without backend or choose a new folder."
      )
    }
    backend <- saved$backend
  } else {
    if (length(list.files(path, all.files = TRUE, no.. = TRUE))) {
      abort(
        "This folder is not empty and has no lakefold.json. Use its original dl_config() or choose an empty folder."
      )
    }
    backend <- backend %||% "duckdb"
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(path)) {
      abort("Unable to create the lake folder.")
    }
    temp <- tempfile("config-", tmpdir = path)
    on.exit(unlink(temp), add = TRUE)
    writeLines(jencode(list(format = 1L, backend = backend)), temp)
    if (!file.rename(temp, manifest)) abort("Unable to save lakefold.json.")
  }
  dl_setup(
    catalog = dl_catalog_duckdb(file.path(path, "metadata.duckdb")),
    storage = dl_storage_local(file.path(path, "data")),
    landing = file.path(path, "landing"),
    backend = backend
  )
}

#' @rdname dl_open
#' @export
dl_close <- function(lake) dl_disconnect(lake)

#' Write data with optional configuration
#'
#' Starts the normal landing, validation and publication workflow. Without a
#' contract, the first successful write establishes a structural schema. Later
#' writes must match that schema. Missing values are allowed; empty tables are
#' blocked. No keys, business rules, owners or freshness deadlines are guessed.
#'
#' Supply `contract` whenever you need business checks or an intentional schema
#' change. Once an execution attempt uses an explicit contract, subsequent writes
#' must supply one too, even if that attempt was blocked. This prevents
#' accidentally dropping its rules. Draft contracts
#' still require [dl_contract_confirm()].
#'
#' Data frames are archived as RDS snapshots. File inputs preserve their original
#' bytes before parsing. Built-in readers support CSV, TSV and RDS. CSV/TSV use
#' base R type inference; use `reader` for specific parsing requirements. The
#' first file may be parsed twice to establish and validate its schema. Readers
#' must be deterministic and must not modify their input.
#'
#' Definition versions are derived automatically. Use [dl_ingest()] when manual
#' control of definition versions is needed. Built-in
#' readers and structural checks can reuse the current release. Custom readers
#' or rules run again by default because captured values and external state
#' cannot be fingerprinted reliably. Supply `code_version` to enable reuse and
#' update it whenever code, dependencies or captured values change.
#' @param lake Connected lake or [dl_config()].
#' @param data Data frame, or path to a local file.
#' @param name Optional asset name. Defaults to the data frame's variable name
#'   or the file name without its extension. Expressions need an explicit name.
#'   Names start with a letter and use letters, digits, underscores or dots.
#' @param contract Optional publication contract. Omit for structural checks.
#' @param reader Optional file reader taking a path and returning a data frame.
#' @param code_version Optional code and dependency version for cache reuse.
#' @param input_contract Optional separate gate before writing Raw.
#' @param cache Optional reuse policy. Defaults to safe reuse for built-in
#'   readers and structural checks; custom callbacks need `code_version` to
#'   enable reuse. `FALSE` always runs validation again.
#' @param ... Arguments passed to [dl_ingest()], such as `business_date`,
#'   `notify`, `layer` and `stop_on_failure`.
#' @returns A `dl_run_result` with status, release ID and quality results.
#'   [dl_read()] returns the published data; [dl_quality()] explains a failure.
#' @seealso [dl_open()], [dl_read()], [dl_ingest()], [dl_pipeline()]
#' @export
#' @examples
#' root <- tempfile("lakefold-")
#' lake <- dl_open(root)
#' orders <- data.frame(id = 1:3, amount = c(25, 75, 50))
#' dl_write(lake, orders)
#' dl_read(lake, "orders")
#' contract <- dl_contract("orders.checked",
#'   columns = c(id = "integer", amount = "numeric"), key = "id")
#' dl_write(lake, orders, contract = contract)
#' dl_close(lake)
#' unlink(root, recursive = TRUE)
dl_write <- function(
  lake,
  data,
  name = NULL,
  contract = NULL,
  reader = NULL,
  code_version = NULL,
  input_contract = NULL,
  cache = NULL,
  ...
) {
  expression <- substitute(data)
  file_input <- is.character(data) && length(data) == 1L && !is.na(data)
  if (!is.data.frame(data) && !file_input) {
    abort("data must be a data frame or a local file path.")
  }
  if (is.null(name)) {
    name <- if (file_input) {
      tools::file_path_sans_ext(basename(data))
    } else if (is.symbol(expression)) {
      as.character(expression)
    } else {
      abort(
        "Supply name when writing a data frame expression, for example name = 'orders'."
      )
    }
  }
  if (
    !is.character(name) ||
      length(name) != 1L ||
      is.na(name) ||
      !grepl("^[A-Za-z][A-Za-z0-9_.]*$", name)
  ) {
    abort(
      "Supply name starting with a letter and using letters, digits, underscores or dots."
    )
  }
  custom_reader <- !is.null(reader)
  if (custom_reader && (!file_input || !is.function(reader))) {
    abort("reader must be a function and is only used with a file path.")
  }
  if (file_input && is.null(reader)) {
    reader <- simple_reader(data)
  }
  for (value in list(contract, input_contract)) {
    if (!is.null(value)) {
      if (!inherits(value, "dl_contract")) {
        abort("Use dl_contract() for contracts.")
      }
      assert_contract_ready(value)
    }
  }
  if (!is.null(code_version)) {
    scalar(code_version, "code_version")
  }
  with_execution_lake(lake, function(con) {
    if (is.null(contract)) {
      contract <- published_schema(con, name)
    }
    source <- NULL
    if (file_input) {
      source <- dl_source(paste0(name, ".file"), data, reader)
      landed <- land_source(con, source)
      source$original_path <- source$path
      source$path <- landed$path
      if (is.null(contract)) {
        prototype <- reader(landed$path)
        if (
          !identical(
            digest::digest(
              file = landed$path,
              algo = "sha256",
              serialize = FALSE
            ),
            landed$hash
          )
        ) {
          abort("Reader modified immutable landing input.")
        }
        contract <- automatic_schema(name, infer_column_types(prototype))
      }
    } else if (is.null(contract)) {
      contract <- automatic_schema(name, infer_column_types(data))
    }
    callbacks <- custom_reader ||
      length(contract$rules) > 0L ||
      length(input_contract$rules) > 0L
    cache <- cache %||% (!callbacks || !is.null(code_version))
    flag(cache, "cache")
    if (cache && callbacks && is.null(code_version)) {
      abort(
        "Supply code_version to cache custom readers or rules, or leave cache unset."
      )
    }
    runtime <- list(
      package = as.character(utils::packageVersion("lakefold")),
      R = as.character(getRversion()),
      duckdb = as.character(utils::packageVersion("duckdb"))
    )
    code_version <- code_version %||% paste0("auto-", fingerprint(runtime))
    version <- paste0(
      "auto-",
      fingerprint(list(
        contract = contract,
        input_contract = input_contract,
        source = source,
        code_version = code_version
      ))
    )
    if (file_input) {
      source$version <- version
      dl_ingest(
        con,
        source,
        contract,
        name,
        version = version,
        code_version = code_version,
        input_contract = input_contract,
        cache = if (cache) "current" else FALSE,
        ...
      )
    } else {
      dl_ingest_data(
        con,
        data,
        contract,
        name,
        code_version = code_version,
        version = version,
        input_contract = input_contract,
        cache = if (cache) "current" else FALSE,
        ...
      )
    }
  })
}

simple_reader <- function(path) {
  switch(
    tolower(tools::file_ext(path)),
    csv = function(path) utils::read.csv(path, check.names = FALSE),
    tsv = function(path) utils::read.delim(path, check.names = FALSE),
    rds = readRDS,
    abort(
      "Supported file types are CSV, TSV and RDS. Supply reader for another format."
    )
  )
}

automatic_schema <- function(name, columns) {
  contract <- dl_contract(
    paste0(name, ".schema"),
    version = paste0("auto-", fingerprint(columns)),
    columns = columns,
    required = character(),
    max_age_hours = NULL
  )
  contract$automatic_schema <- TRUE
  contract
}

published_schema <- function(lake, name) {
  definitions <- query(
    lake,
    paste(
      "SELECT DISTINCT a.definition FROM",
      meta(lake, "assets"),
      "a JOIN",
      meta(lake, "runs"),
      "r ON a.fingerprint = r.definition_hash",
      "AND a.id = r.pipeline WHERE a.kind = 'pipeline' AND r.asset = ?"
    ),
    list(name)
  )
  for (definition in definitions$definition) {
    contract <- jdecode(definition)$steps$validate
    if (!is.null(contract) && !isTRUE(contract$automatic_schema)) {
      abort(
        "This asset uses an explicit contract. Supply contract to keep its checks active."
      )
    }
  }
  release <- tryCatch(resolve_release(lake, name), dl_no_release = function(e) {
    NULL
  })
  if (is.null(release)) {
    return(NULL)
  }
  reference <- strsplit(release$contract[[1]], "@", fixed = TRUE)[[1]]
  record <- query(
    lake,
    paste(
      "SELECT definition, fingerprint FROM",
      meta(lake, "assets"),
      "WHERE kind = 'contract' AND id = ? AND version = ?"
    ),
    as.list(reference)
  )
  if (nrow(record) != 1L) {
    abort("Published contract metadata is missing.")
  }
  definition <- jdecode(record$definition[[1]])
  if (!isTRUE(definition$automatic_schema)) {
    abort(
      "This asset uses an explicit contract. Supply contract to keep its checks active."
    )
  }
  contract <- automatic_schema(
    name,
    unlist(definition$columns, use.names = TRUE)
  )
  if (!identical(fingerprint(contract), record$fingerprint[[1]])) {
    abort("Automatic schema metadata does not match its registered definition.")
  }
  contract
}

#' Read a published asset
#'
#' Returns the latest successfully published data as a tibble. Failed writes
#' leave that release intact. Set `lazy = TRUE` to filter or aggregate in the
#' database before collecting large data; keep the connection open while using
#' a lazy table. Use `release` to read an exact historical version.
#' @param lake Connected lake.
#' @param name Published asset name.
#' @param release Optional release ID. Defaults to the latest release.
#' @param lazy Return a lazy database table instead of collecting all rows.
#' @returns A tibble, or a lazy `tbl_sql` when `lazy = TRUE`.
#' @seealso [dl_write()], [dl_tbl()], [dl_releases()]
#' @export
#' @examples
#' root <- tempfile("lakefold-")
#' lake <- dl_open(root)
#' dl_write(lake, data.frame(id = 1:3), "orders")
#' dl_read(lake, "orders")
#' dl_read(lake, "orders", lazy = TRUE) |>
#'   dplyr::filter(id > 1) |>
#'   dplyr::collect()
#' dl_close(lake)
#' unlink(root, recursive = TRUE)
dl_read <- function(lake, name, release = NULL, lazy = FALSE) {
  flag(lazy, "lazy")
  data <- dl_tbl(lake, name, release)
  if (lazy) data else dplyr::collect(data)
}
