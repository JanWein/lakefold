# A model keeps the ordinary product fields and specializes execution/output.
new_model_product <- function(x, data, contracts) {
  need("dm")
  tables <- as.list(data)
  if (!length(tables)) {
    abort("A model product needs at least one table.")
  }
  invisible(lapply(names(tables), asset_id))
  if (is.null(contracts)) {
    contracts <- list()
  }
  if (
    !is.list(contracts) ||
      (length(contracts) &&
        (is.null(names(contracts)) ||
          anyNA(names(contracts)) ||
          anyDuplicated(names(contracts)) ||
          any(!names(contracts) %in% names(tables))))
  ) {
    abort("contracts must be named by model table, without duplicates.")
  }
  pk <- dm::dm_get_all_pks(data)
  fk <- dm::dm_get_all_fks(data)
  x$primary_keys <- stats::setNames(lapply(pk$pk_col, as.character), pk$table)
  x$foreign_keys <- lapply(seq_len(nrow(fk)), function(i) {
    list(
      table = fk$child_table[[i]],
      columns = as.character(fk$child_fk_cols[[i]]),
      ref_table = fk$parent_table[[i]],
      ref_columns = as.character(fk$parent_key_cols[[i]])
    )
  })
  x$sources <- stats::setNames(
    lapply(names(tables), function(name) {
      product(
        paste(x$id, name, sep = "."),
        tables[[name]],
        contract = contracts[[name]],
        source_name = name
      )
    }),
    names(tables)
  )
  class(x) <- c("tw_model_product", class(x))
  x
}

#' @export
validate.tw_model_product <- function(data, contract = NULL, ...) {
  rlang::check_dots_empty()
  if (
    !is.null(contract) ||
      !is.null(data$contract) ||
      length(data$quality) ||
      length(data$transforms) ||
      length(data$catalogs)
  ) {
    abort(
      "Configure checks and transformations on the model's table products. Select a table with product(..., table = ) after trial() or publish()."
    )
  }
  if (
    !length(data$sources) ||
      anyDuplicated(names(data$sources)) ||
      !all(vapply(
        data$sources,
        function(x) {
          inherits(x, "tw_product") &&
            !inherits(x, "tw_model_product")
        },
        logical(1)
      ))
  ) {
    abort("Model members must be named table products.")
  }
  invisible(lapply(data$sources, validate))
  if (!is.null(data$target)) {
    if (
      !inherits(data$target, "tw_lake_target") ||
        length(data$target$partition_by)
    ) {
      abort("Model products publish complete snapshots to a lake target.")
    }
    check_component(data$target)
  }
  data
}

#' @export
inspect.tw_model_product <- function(x, ...) {
  list(
    id = x$id,
    version = x$version,
    kind = "model_product",
    tables = lapply(x$sources, inspect),
    primary_keys = x$primary_keys,
    foreign_keys = x$foreign_keys,
    target = inspect(x$target)
  )
}

#' @export
print.tw_model_product <- function(x, ...) {
  cat(
    "<model product>",
    x$id,
    "| tables:",
    paste(names(x$sources), collapse = ", "),
    "\n"
  )
  invisible(x)
}

#' @export
run.tw_model_product <- function(
  pipeline,
  lake = NULL,
  stop_on_failure = TRUE,
  execution = NULL,
  data = NULL,
  sources = NULL,
  previous = NULL,
  ...
) {
  rlang::check_dots_empty()
  flag(stop_on_failure, "stop_on_failure")
  if (!is.null(data)) {
    abort("Replace model tables with sources = list(table_name = delivery).")
  }
  x <- pipeline
  if (!is.null(sources)) {
    x <- replace_sources_list(x, sources)
  }
  execution <- product_execution(x, execution)
  x <- apply_execution_defaults(x, execution)
  if (!is.null(lake)) {
    x <- set_target(x, lake)
  }
  x <- validate(x)
  result <- run_result(uid(), "completed")
  class(result) <- c("tw_model_result", class(result))
  result$asset <- x$id
  result$primary_keys <- x$primary_keys
  result$foreign_keys <- x$foreign_keys
  result$members <- lapply(x$sources, function(member) trial(member))
  checks <- lapply(names(result$members), function(name) {
    out <- quality(result$members[[name]])
    out$rule <- paste(name, out$rule, sep = "/")
    out
  })
  result$quality <- dplyr::bind_rows(checks)
  good <- vapply(
    result$members,
    function(m) m$status == "completed",
    logical(1)
  )
  if (!all(good)) {
    result$status <- "blocked"
  } else {
    candidate <- dm::dm(!!!lapply(result$members, collect))
    checked <- tryCatch(
      dm_keys(candidate, x$primary_keys, x$foreign_keys, TRUE),
      error = identity
    )
    if (inherits(checked, "error")) {
      result$status <- "blocked"
      result$error <- checked
      result$quality <- dplyr::bind_rows(
        result$quality,
        quality_row(
          "relationships",
          "failed",
          engine = "dm",
          message = "Model keys or references failed. Inspect result$error$checks."
        )
      )
    } else {
      result$data <- checked
      result$quality <- dplyr::bind_rows(
        result$quality,
        quality_row("relationships", "passed", engine = "dm")
      )
    }
  }
  if (result$status == "completed" && !is.null(x$target)) {
    result <- tryCatch(
      publish_model_result(x, result, previous),
      error = function(e) {
        result$status <- "error"
        result$error <- e
        if (stop_on_failure) {
          abort(
            conditionMessage(e),
            class = class(e)[[1]],
            parent = e,
            result = result
          )
        }
        result
      }
    )
  } else if (!is.null(previous) && is.null(x$target)) {
    abort("previous is available only when publishing to a lake.")
  }
  if (stop_on_failure && result$status == "blocked") {
    abort(
      paste("Model", x$id, "failed checks. Inspect quality_report(result)."),
      "tw_model_failed",
      result = result
    )
  }
  result
}

#' @export
collect.tw_model_result <- function(x, ...) {
  rlang::check_dots_empty()
  if (!x$status %in% c("completed", "published")) {
    abort(
      "The model failed checks. Inspect quality_report(result) and quality_rows(result)."
    )
  }
  if (!is.null(x$data)) {
    return(x$data)
  }
  with_model_lake(x, function(lake) {
    read_model_release(lake, x$asset, x$release_id)
  })
}

with_model_lake <- function(x, fn) {
  lake <- x$output_lake
  if (is.null(lake) || !DBI::dbIsValid(lake$con)) {
    lake <- connect_lake(x$output_config, read_only = TRUE)
    on.exit(close_lake(lake), add = TRUE)
  }
  fn(lake)
}

model_member_result <- function(x, table) {
  scalar(table, "table")
  if (
    !inherits(x, "tw_model_result") ||
      !x$status %in% c("completed", "published")
  ) {
    abort("Select a table from a successful trial() or publish() model result.")
  }
  if (!table %in% names(x$members)) {
    abort(paste(
      "Unknown model table. Choose:",
      paste(names(x$members), collapse = ", ")
    ))
  }
  x$members[[table]]
}

publish_model_result <- function(x, result, previous) {
  target <- x$target
  lake <- target$destination
  own <- !inherits(lake, "tw_lake")
  if (own) {
    lake <- if (inherits(lake, "tw_config")) {
      connect_lake(lake)
    } else {
      open_lake(lake)
    }
    on.exit(close_lake(lake), add = TRUE)
  }
  assert_writable(lake)
  check_previous_release(lake, x$id, previous)
  prior <- tryCatch(resolve_release(lake, x$id), tw_no_release = function(e) {
    NULL
  })
  if (!is.null(prior) && !startsWith(prior$table_name[[1]], "model_")) {
    abort(
      "This name already publishes a table. Choose a distinct model product name."
    )
  }
  tables <- as.list(result$data)
  layer <- target$layer
  if (!layer %in% lake$config$layers) {
    abort("Model target layer is missing from the lake.")
  }
  definition <- inspect(x)
  definition$target <- NULL
  definition$version <- if (x$automatic_version) {
    paste0("auto-", fingerprint(definition))
  } else {
    x$version
  }
  register(lake, definition)
  run <- new_run(
    lake,
    x$id,
    x$id,
    fingerprint(definition),
    x$code_version %||% "unversioned-no-cache"
  )
  release <- uid()
  members <- list()
  success <- FALSE
  on.exit(
    if (!success) {
      finish_run(
        lake,
        run,
        "error",
        "Model publication failed; prior model remains available."
      )
    },
    add = TRUE,
    after = FALSE
  )
  DBI::dbWithTransaction(lake$con, {
    for (name in names(tables)) {
      member <- x$sources[[name]]
      asset <- paste(x$id, name, sep = ".")
      old <- tryCatch(
        resolve_release(lake, asset),
        tw_no_release = function(e) NULL
      )
      if (!is.null(old)) {
        origin <- metadata_filter(lake, "runs", run_id = old$run_id[[1]])
        if (nrow(origin) != 1L || origin$pipeline[[1]] != x$id) {
          abort(paste("Model member name belongs to another product:", asset))
        }
      }
      member_release <- uid()
      table <- paste0("member_", member_release)
      contract <- member$contract %||%
        automatic_schema(
          asset,
          automatic_types(infer_column_types(tables[[name]]))
        )
      if (is.null(member$contract) && !is.null(old)) {
        ref <- strsplit(old$contract[[1]], "@", fixed = TRUE)[[1]]
        saved <- query(
          lake,
          paste(
            "SELECT definition FROM",
            meta(lake, "assets"),
            "WHERE kind = 'contract' AND id = ? AND version = ?"
          ),
          as.list(ref)
        )
        if (nrow(saved) != 1L) {
          abort("Published member contract is missing.")
        }
        prior_contract <- jdecode(saved$definition[[1]])
        if (!isTRUE(prior_contract$automatic_schema)) {
          abort(paste(
            "Keep the explicit contract for model table",
            name,
            "in contracts or its replacement product."
          ))
        }
        contract <- automatic_schema(
          asset,
          automatic_types(unlist(prior_contract$columns, use.names = TRUE))
        )
        if (!quality_ok(validate(tables[[name]], contract))) {
          abort(paste(
            "Model table",
            name,
            "changed its established schema. Supply an explicit reviewed contract."
          ))
        }
      }
      register(lake, contract)
      DBI::dbWriteTable(
        lake$con,
        table_id(layer, table),
        as.data.frame(tables[[name]])
      )
      insert_meta(
        lake,
        "releases",
        list(
          release_id = member_release,
          asset = asset,
          schema_name = layer,
          table_name = table,
          run_id = run,
          published_at = now(),
          contract = paste(contract$id, contract$version, sep = "@"),
          definition_hash = fingerprint(definition),
          input_hash = fingerprint(tables[[name]]),
          quality = "passed",
          business_date = NA_character_,
          parent_release = if (is.null(old)) {
            NA_character_
          } else {
            old$release_id[[1]]
          }
        )
      )
      members[[name]] <- list(asset = asset, release_id = member_release)
      insert_meta(
        lake,
        "lineage_edges",
        list(
          run_id = run,
          from_id = asset,
          from_version = member_release,
          to_id = x$id,
          to_version = release,
          relation = "model_member"
        )
      )
    }
    manifest <- list(
      format = 1L,
      members = members,
      primary_keys = x$primary_keys,
      foreign_keys = x$foreign_keys
    )
    table <- paste0("model_", release)
    DBI::dbWriteTable(
      lake$con,
      table_id(layer, table),
      data.frame(manifest = jencode(manifest))
    )
    insert_meta(
      lake,
      "releases",
      list(
        release_id = release,
        asset = x$id,
        schema_name = layer,
        table_name = table,
        run_id = run,
        published_at = now(),
        contract = "",
        definition_hash = fingerprint(definition),
        input_hash = fingerprint(tables),
        quality = "passed",
        business_date = NA_character_,
        parent_release = if (is.null(prior)) {
          NA_character_
        } else {
          prior$release_id[[1]]
        }
      )
    )
    for (i in seq_len(nrow(result$quality))) {
      row <- as.list(result$quality[
        i,
        intersect(
          names(result$quality),
          DBI::dbListFields(lake$con, table_id("_dl", "quality_results"))
        ),
        drop = FALSE
      ])
      insert_meta(
        lake,
        "quality_results",
        c(
          list(run_id = run, contract = x$id),
          row[setdiff(names(row), c("run_id", "contract"))]
        )
      )
    }
    finish_run(lake, run, "published", release = release)
  })
  success <- TRUE
  result$run_id <- run
  result$release_id <- release
  result$status <- "published"
  result$output_config <- lake$config
  if (!own) {
    result$output_lake <- lake
  }
  result$data <- NULL
  result$members <- lapply(members, function(ref) {
    out <- run_result(run, "published", ref$release_id)
    out$asset <- ref$asset
    out$output_config <- lake$config
    if (!own) {
      out$output_lake <- lake
    }
    out
  })
  result
}

read_model_release <- function(lake, asset, release = NULL) {
  need("dm")
  ref <- resolve_release(lake, asset, release)
  if (!startsWith(ref$table_name[[1]], "model_")) {
    abort("This release is not a model product.")
  }
  manifest <- jdecode(query(
    lake,
    paste(
      "SELECT manifest FROM",
      table_sql(lake, ref$schema_name[[1]], ref$table_name[[1]])
    )
  )$manifest[[1]])
  if (!identical(manifest$format, 1L)) {
    abort("Unsupported model manifest format.")
  }
  tables <- lapply(manifest$members, function(x) {
    read_release(lake, x$asset, x$release_id)
  })
  pk <- lapply(manifest$primary_keys, unlist, use.names = FALSE)
  fk <- lapply(manifest$foreign_keys, function(x) {
    x$columns <- unlist(x$columns, use.names = FALSE)
    x$ref_columns <- unlist(x$ref_columns, use.names = FALSE)
    x
  })
  dm_keys(dm::dm(!!!tables), pk, fk, FALSE)
}

#' @export
explain.tw_model_product <- function(x, ...) {
  print(x)
  cat(
    "Define table checks with contracts = list(...). Replace deliveries by table name.\n"
  )
  invisible(inspect(x))
}
