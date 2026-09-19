#' Define a data product
#' @param id,version Product identity and version.
#' @param inputs Named character vector of input asset ids.
#' @param build Function of a named list of lazy input tables; returns a lazy
#'   table or a data frame. Inputs are pinned to releases before build runs.
#' @param contract Product contract.
#' @param owner,description Metadata.
#' @param code_version Version of all build code and dependencies.
#' @param layer Output schema.
#' @return A product specification.
#' @export
#' @examples
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' product <- dl_product("orders.copy", c(orders = "orders"),
#'   build = function(tables) tables$orders, contract = contract,
#'   code_version = "v1")
#' product
dl_product <- function(
  id,
  inputs,
  build,
  contract,
  version = "1.0.0",
  owner = contract$owner,
  description = contract$description,
  code_version,
  layer = "products"
) {
  asset_id(id)
  scalar(version, "version")
  scalar(code_version, "code_version")
  ident(layer)
  if (
    !is.character(inputs) ||
      !length(inputs) ||
      is.null(names(inputs)) ||
      anyDuplicated(names(inputs)) ||
      any(!nzchar(names(inputs)))
  ) {
    abort("inputs must be a named character vector of assets.")
  }
  invisible(lapply(inputs, asset_id))
  if (!is.function(build) || !inherits(contract, "dl_contract")) {
    abort("A build function and contract are required.")
  }
  structure(
    list(
      id = id,
      version = version,
      kind = "product",
      inputs = as.list(inputs),
      build = build,
      contract = contract,
      owner = owner,
      description = description,
      code_version = code_version,
      layer = layer
    ),
    class = "dl_product"
  )
}

#' Build, validate and publish a product
#' @param lake Connected lake.
#' @param product Product specification.
#' @param releases Optional named vector of explicit input release ids, keyed
#'   by input alias.
#' @param business_date Reporting date.
#' @param notify Optional function(event).
#' @param stop_on_failure Fail the job after metadata has been saved.
#' @return Run result.
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
#' product <- dl_product("orders.copy", c(orders = "orders"),
#'   build = function(tables) tables$orders, contract = contract,
#'   code_version = "v1")
#' dl_build(lake, product)
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_build <- function(
  lake,
  product,
  releases = NULL,
  business_date = NA_character_,
  notify = NULL,
  stop_on_failure = TRUE
) {
  assert_lake(lake)
  if (!inherits(product, "dl_product")) {
    abort("product must be a dl_product.")
  }
  if (!product$layer %in% lake$config$layers) {
    abort("Product layer not configured.")
  }
  if (
    !is.null(releases) &&
      (!setequal(names(releases), names(product$inputs)) || anyNA(releases))
  ) {
    abort("releases must pin every input alias.")
  }
  dl_register(lake, product$contract)
  dl_register(lake, product)
  dh <- fingerprint(product)
  contract <- product$contract
  run <- new_run(lake, product$id, product$id, dh, product$code_version)
  result <- tryCatch(
    {
      refs <- lapply(names(product$inputs), function(alias) {
        resolve_release(
          lake,
          product$inputs[[alias]],
          if (!is.null(releases)) releases[[alias]] else NULL
        )
      })
      names(refs) <- names(product$inputs)
      ih <- fingerprint(list(
        releases = lapply(refs, function(x) x$release_id[[1]]),
        business_date = as.character(business_date)
      ))
      exec(
        lake,
        paste("UPDATE", meta(lake, "runs"), "SET input_hash=? WHERE run_id=?"),
        list(ih, run)
      )
      for (alias in names(refs)) {
        insert_meta(
          lake,
          "inputs",
          list(
            run_id = run,
            source = product$inputs[[alias]],
            source_version = refs[[alias]]$release_id[[1]],
            fingerprint = refs[[alias]]$input_hash[[1]],
            original_name = "",
            landed_path = "",
            received_at = now(),
            business_date = as.character(business_date)
          )
        )
      }
      cached <- find_cached(lake, product$id, ih, dh)
      if (nrow(cached)) {
        finish_run(lake, run, "cached", release = cached$release_id[[1]])
        run_result(run, "cached", cached$release_id[[1]])
      } else {
        tables <- lapply(refs, function(r) {
          dl_tbl(lake, r$asset[[1]], r$release_id[[1]])
        })
        pub <- list(asset = product$id, mode = "replace", layer = product$layer)
        candidate <- compose_candidate(lake, product$build(tables), pub, run)
        quality <- dl_validate(candidate$data, contract)
        persist_quality(lake, run, contract, quality)
        if (!quality_ok(quality)) {
          finish_run(
            lake,
            run,
            "blocked",
            "Product quality gate blocked publication."
          )
          emit_event(
            lake,
            run,
            product$id,
            "quality_failed",
            contract$producer,
            "Product publication blocked; inspect quality_results.",
            notify
          )
          run_result(run, "blocked", quality = quality)
        } else {
          edges <- lapply(refs, function(r) {
            list(from_id = r$asset[[1]], from_version = r$release_id[[1]])
          })
          publish_candidate(
            lake,
            run,
            pub,
            candidate,
            contract,
            quality,
            dh,
            ih,
            business_date,
            edges
          )
        }
      }
    },
    error = function(e) {
      finish_run(lake, run, "error", "Product execution failed.")
      emit_event(
        lake,
        run,
        product$id,
        "run_error",
        contract$producer,
        "Product execution failed; inspect input availability and build code.",
        notify
      )
      x <- run_result(run, "error")
      x$error <- e
      x
    }
  )
  if (stop_on_failure && !result$status %in% c("published", "cached")) {
    abort(
      paste("Product run", run, "ended with", result$status),
      "dl_run_failed",
      result = result,
      parent = result$error
    )
  }
  result
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
#' model <- dl_model(lake, c(orders = "orders"),
#'   primary_keys = list(orders = "order_id"))
#' model
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_model <- function(
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
    !!!lapply(refs, function(r) dl_tbl(lake, r$asset[[1]], r$release_id[[1]]))
  )
  model <- dm_keys(model, primary_keys, foreign_keys, check)
  attr(model, "dl_releases") <- lapply(refs, function(r) r$release_id[[1]])
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
        "dl_model_invalid",
        checks = checks
      )
    }
  }
  model
}
