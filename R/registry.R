registry_init <- function(lake) {
  schemas <- list(
    assets = "id VARCHAR, version VARCHAR, kind VARCHAR, owner VARCHAR, description VARCHAR, definition VARCHAR, fingerprint VARCHAR, registered_at VARCHAR",
    runs = "run_id VARCHAR, pipeline VARCHAR, asset VARCHAR, status VARCHAR, started_at VARCHAR, finished_at VARCHAR, input_hash VARCHAR, definition_hash VARCHAR, code_version VARCHAR, message VARCHAR, release_id VARCHAR",
    inputs = "run_id VARCHAR, source VARCHAR, source_version VARCHAR, fingerprint VARCHAR, original_name VARCHAR, landed_path VARCHAR, received_at VARCHAR, business_date VARCHAR",
    quality_results = "run_id VARCHAR, contract VARCHAR, rule VARCHAR, status VARCHAR, severity VARCHAR, n_failed DOUBLE, n_total DOUBLE, threshold DOUBLE, message VARCHAR",
    releases = "release_id VARCHAR, asset VARCHAR, schema_name VARCHAR, table_name VARCHAR, run_id VARCHAR, published_at VARCHAR, contract VARCHAR, definition_hash VARCHAR, input_hash VARCHAR, quality VARCHAR, business_date VARCHAR, parent_release VARCHAR",
    lineage_edges = "run_id VARCHAR, from_id VARCHAR, from_version VARCHAR, to_id VARCHAR, to_version VARCHAR, relation VARCHAR",
    events = "event_id VARCHAR, run_id VARCHAR, asset VARCHAR, type VARCHAR, recipient VARCHAR, created_at VARCHAR, status VARCHAR, message VARCHAR",
    reports = "id VARCHAR, created_at VARCHAR, manifest VARCHAR"
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
}

#' Read framework metadata
#' @param lake Connected lake.
#' @param table Metadata table name.
#' @return A tibble.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' dl_registry(lake, "runs")
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_registry <- function(
  lake,
  table = c(
    "assets",
    "runs",
    "inputs",
    "quality_results",
    "releases",
    "lineage_edges",
    "events",
    "reports"
  )
) {
  assert_lake(lake)
  table <- match.arg(table)
  query(lake, paste("SELECT * FROM", meta(lake, table)))
}

#' Register a versioned definition
#' @param lake Connected lake.
#' @param object A contract, source, product, metric or pipeline definition.
#' @return The definition, invisibly. Reusing a version with changed content
#'   errors.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' dl_register(lake, contract)
#' dl_registry(lake, "assets")
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_register <- function(lake, object) {
  assert_lake(lake)
  if (is.null(object$id) || is.null(object$version) || is.null(object$kind)) {
    abort("Object is not a registerable definition.")
  }
  definition <- object
  definition$config <- NULL
  h <- fingerprint(definition)
  old <- query(
    lake,
    paste(
      "SELECT fingerprint FROM",
      meta(lake, "assets"),
      "WHERE id = ? AND version = ? AND kind = ?"
    ),
    list(object$id, object$version, object$kind)
  )
  if (nrow(old)) {
    if (any(old$fingerprint != h)) {
      abort(paste(
        "Definition changed without a version bump:",
        object$id,
        object$version
      ))
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
    abort(paste("No published release for", asset), "dl_no_release")
  }
  rows
}

#' Query a published immutable data release
#' @param lake Connected lake.
#' @param asset Asset id.
#' @param release Release id; NULL selects latest.
#' @return A lazy dbplyr table.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dl_source("orders.file", path, reader = utils::read.csv)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' release <- dl_ingest(lake, source, contract, "orders", code_version = "v1")
#' dl_tbl(lake, "orders", release$release_id) |> dplyr::collect()
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_tbl <- function(lake, asset, release = NULL) {
  r <- resolve_release(lake, asset_id(asset), release)
  dplyr::tbl(lake$con, table_id(r$schema_name[[1]], r$table_name[[1]]))
}
