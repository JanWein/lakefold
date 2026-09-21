registry_init <- function(lake) {
  registry_table <- meta(lake, "schema_version")
  exec(
    lake,
    paste0(
      "CREATE TABLE IF NOT EXISTS ",
      registry_table,
      " (version INTEGER, applied_at VARCHAR)"
    )
  )
  versions <- query(lake, paste("SELECT version FROM", registry_table))$version
  if (anyNA(versions) || any(versions > 4L)) {
    abort(
      "Registry schema is newer than this tidyweave version supports.",
      "tw_registry_version"
    )
  }
  schemas <- list(
    assets = "id VARCHAR, version VARCHAR, kind VARCHAR, owner VARCHAR, description VARCHAR, definition VARCHAR, fingerprint VARCHAR, registered_at VARCHAR",
    runs = "run_id VARCHAR, pipeline VARCHAR, asset VARCHAR, status VARCHAR, started_at VARCHAR, finished_at VARCHAR, input_hash VARCHAR, definition_hash VARCHAR, code_version VARCHAR, message VARCHAR, release_id VARCHAR",
    inputs = "run_id VARCHAR, source VARCHAR, source_version VARCHAR, fingerprint VARCHAR, original_name VARCHAR, landed_path VARCHAR, received_at VARCHAR, business_date VARCHAR",
    quality_results = "run_id VARCHAR, contract VARCHAR, rule VARCHAR, status VARCHAR, severity VARCHAR, n_failed DOUBLE, n_total DOUBLE, threshold DOUBLE, message VARCHAR",
    releases = "release_id VARCHAR, asset VARCHAR, schema_name VARCHAR, table_name VARCHAR, run_id VARCHAR, published_at VARCHAR, contract VARCHAR, definition_hash VARCHAR, input_hash VARCHAR, quality VARCHAR, business_date VARCHAR, parent_release VARCHAR",
    lineage_edges = "run_id VARCHAR, from_id VARCHAR, from_version VARCHAR, to_id VARCHAR, to_version VARCHAR, relation VARCHAR",
    events = "event_id VARCHAR, run_id VARCHAR, asset VARCHAR, type VARCHAR, recipient VARCHAR, created_at VARCHAR, status VARCHAR, message VARCHAR",
    reports = "id VARCHAR, created_at VARCHAR, manifest VARCHAR",
    run_owners = "run_id VARCHAR, host VARCHAR, pid INTEGER, boot VARCHAR, process_start VARCHAR"
  )
  for (name in names(schemas)) {
    exec(
      lake,
      paste0(
        "CREATE TABLE IF NOT EXISTS ",
        meta(lake, name),
        " (",
        schemas[[name]],
        ")"
      )
    )
  }
  DBI::dbWithTransaction(lake$con, {
    columns <- DBI::dbListFields(lake$con, table_id("_dl", "quality_results"))
    additions <- c(
      engine = "'legacy'",
      stage = "'candidate'",
      segment = "''",
      details = "''"
    )
    for (column in setdiff(names(additions), columns)) {
      exec(
        lake,
        paste(
          "ALTER TABLE",
          meta(lake, "quality_results"),
          "ADD COLUMN",
          qident(lake, column),
          "VARCHAR DEFAULT",
          additions[[column]]
        )
      )
    }
    if (!4L %in% versions) {
      insert_meta(
        lake,
        "schema_version",
        list(version = 4L, applied_at = now())
      )
    }
  })
}

#' Read framework metadata
#' @param lake Connected lake.
#' @param table Metadata table name.
#' @return A tibble.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' registry(lake, "runs")
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
registry <- function(
  lake,
  table = c(
    "assets",
    "runs",
    "inputs",
    "quality_results",
    "releases",
    "lineage_edges",
    "events",
    "reports",
    "schema_version",
    "run_owners"
  )
) {
  assert_lake(lake)
  if (length(table) == 1L && table %in% c("ru", "run")) {
    table <- "runs"
  }
  table <- match.arg(table)
  query(lake, paste("SELECT * FROM", meta(lake, table)))
}

#' Register a versioned definition
#' @param lake Connected lake.
#' @param object A contract, source, product, metric or pipeline definition.
#' @return The definition, invisibly. Reusing a version with changed content
#'   errors.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' contract <- contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' register(lake, contract)
#' registry(lake, "assets")
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
register <- function(lake, object) {
  assert_writable(lake)
  if (inherits(object, "tw_contract")) {
    assert_contract_ready(object)
  }
  if (is.null(object$id) || is.null(object$version) || is.null(object$kind)) {
    abort("Object is not a registerable definition.")
  }
  definition <- object
  definition$config <- NULL
  h <- fingerprint(definition)
  old <- query(
    lake,
    paste(
      "SELECT fingerprint, definition FROM",
      meta(lake, "assets"),
      "WHERE id = ? AND version = ? AND kind = ?"
    ),
    list(object$id, object$version, object$kind)
  )
  if (nrow(old)) {
    if (any(old$fingerprint != h)) {
      if (
        inherits(object, "tw_metric") &&
          any(vapply(
            old$definition,
            function(x) is.character(jdecode(x)$expr),
            logical(1)
          ))
      ) {
        abort(
          "Legacy metric formulas used abbreviated labels. Register a new metric version; historical reports remain readable.",
          "tw_legacy_metric"
        )
      }
      abort(
        paste(
          "Definition changed without a version bump:",
          object$id,
          object$version
        ),
        "tw_definition_changed",
        definition_id = object$id,
        definition_version = object$version
      )
    }
  } else {
    insert_meta(
      lake,
      "assets",
      list(
        id = object$id,
        version = object$version,
        kind = object$kind,
        owner = object$owner %||% "",
        description = object$description %||% "",
        definition = jencode(definition),
        fingerprint = h,
        registered_at = now()
      )
    )
  }
  invisible(object)
}

resolve_release <- function(lake, asset, release = NULL) {
  sql <- paste("SELECT * FROM", meta(lake, "releases"), "WHERE asset = ?")
  params <- list(asset)
  if (!is.null(release)) {
    sql <- paste(sql, "AND release_id = ?")
    params <- c(params, list(release))
  }
  rows <- query(
    lake,
    paste(sql, "ORDER BY published_at DESC, release_id DESC LIMIT 1"),
    params
  )
  if (!nrow(rows)) {
    abort(paste("No published release for", asset), "tw_no_release")
  }
  rows
}

#' Query a published immutable data release
#' @param src Connected lake.
#' @param asset Asset id.
#' @param release Release id; NULL selects latest.
#' @param ... Reserved for extensions.
#' @return A lazy dbplyr table.
#' @name tbl
#' @importFrom dplyr tbl
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- source_file("orders.file", path, reader = utils::read.csv)
#' contract <- contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- product("orders", contract = contract, code_version = "v1") |>
#'   add_source(source) |> publish(to = lake)
#' tbl(lake, "orders", release$release_id) |> dplyr::collect()
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
dplyr::tbl

#' @rdname tbl
#' @export
tbl.tw_lake <- function(src, asset, release = NULL, ...) {
  rlang::check_dots_empty()
  lake <- src
  r <- resolve_release(lake, asset_id(asset), release)
  dplyr::tbl(lake$con, table_id(r$schema_name[[1]], r$table_name[[1]]))
}
