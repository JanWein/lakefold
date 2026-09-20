#' Define a composable data product
#'
#' Add named sources, ordinary transformation functions and optional checks or
#' a target. Nothing executes until [run()] or [publish()]. Products can be
#' sources of other products; shared dependencies run once per execution.
#' @param id Product identity, unique within a dependency graph.
#' @param data Optional table, path, source adapter, product, or successful run.
#'   Successful lake runs are pinned to their exact published release.
#' @param contract Optional contract, named type vector or prototype list.
#' @param version Optional immutable definition version. When omitted, lake
#'   publication derives a technical version from the definition.
#' @param owner,description Optional metadata, otherwise inherited from contract.
#' @param code_version Optional code and dependency version. Required only when
#'   explicitly reusing a previously published lake release with `cache = TRUE`.
#' @param source_name Optional name for `data`. Defaults to the product ID for
#'   ordinary inputs, or the upstream product ID for a nested product.
#' @param execution Optional connection-free [execution_config()] stored on this
#'   definition. Used when it is the root of [run()], [publish()] or [ingest()].
#'   An explicit execution argument overrides these defaults.
#' @returns A `tw_product`, ready for composition, inspection and execution.
#' @export
#' @examples
#' orders <- product("orders") |> add_source(data.frame(id = 1:2))
#' product("summary") |>
#'   add_source(orders) |>
#'   add_transform(function(data) data.frame(rows = nrow(data))) |>
#'   run() |>
#'   collect()
product <- function(
  id,
  data = NULL,
  contract = NULL,
  version = "1.0.0",
  owner = NULL,
  description = NULL,
  code_version = NULL,
  source_name = NULL,
  execution = NULL
) {
  x <- new_product(
    id,
    contract,
    version,
    code_version,
    automatic_version = missing(version),
    owner = owner,
    description = description
  )
  execution <- validate_stored_execution(execution)
  if (!is.null(execution)) {
    attr(x, "tw_execution_config") <- execution
  }
  if (!is.null(source_name)) {
    scalar(source_name, "source_name")
  }
  if (is.null(data) && !is.null(source_name)) {
    abort(
      "source_name requires data. Name a later source with add_source(name = )."
    )
  }
  if (!is.null(data)) {
    source_name <- source_name %||%
      if (inherits(data, "tw_product")) data$id else id
    x <- add_source(x, data, name = source_name)
  }
  x
}

#' Create and validate a relational dm model from pinned releases
#' @param lake Connected lake.
#' @param tables Named character vector of asset ids.
#' @param primary_keys Named list of character vectors, keyed by table alias.
#' @param foreign_keys List of lists containing table, columns, ref_table,
#'   ref_columns.
#' @param releases Optional named vector pinning all table releases.
#' @param check Validate all declared keys and relationships.
#' @return A dm object containing lazy tables. No automatic flattening is done.
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
#' model <- model(lake, c(orders = "orders"),
#'   primary_keys = list(orders = "order_id"))
#' model
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
model <- function(
  lake,
  tables,
  primary_keys = list(),
  foreign_keys = list(),
  releases = NULL,
  check = TRUE
) {
  need("dm")
  if (is.null(names(tables)) || anyDuplicated(names(tables))) {
    abort("tables must be named uniquely.")
  }
  if (!is.null(releases) && !setequal(names(releases), names(tables))) {
    abort("Pin all model table releases.")
  }
  refs <- lapply(names(tables), function(n) {
    resolve_release(
      lake,
      tables[[n]],
      if (is.null(releases)) NULL else releases[[n]]
    )
  })
  names(refs) <- names(tables)
  model <- dm::dm(
    !!!lapply(refs, function(r) tbl(lake, r$asset[[1]], r$release_id[[1]]))
  )
  model <- dm_keys(model, primary_keys, foreign_keys, check)
  attr(model, "tw_releases") <- lapply(refs, function(r) r$release_id[[1]])
  model
}

dm_keys <- function(model, primary_keys, foreign_keys, check) {
  for (name in names(primary_keys)) {
    model <- dm::dm_add_pk(
      model,
      !!rlang::sym(name),
      dplyr::all_of(!!primary_keys[[name]])
    )
  }
  for (fk in foreign_keys) {
    model <- dm::dm_add_fk(
      model,
      !!rlang::sym(fk$table),
      dplyr::all_of(!!fk$columns),
      !!rlang::sym(fk$ref_table),
      dplyr::all_of(!!fk$ref_columns)
    )
  }
  if (check) {
    checks <- dm::dm_examine_constraints(model)
    if (nrow(checks) && !all(checks$is_key)) {
      abort(
        "Relational constraints failed.",
        "tw_model_invalid",
        checks = checks
      )
    }
  }
  model
}
