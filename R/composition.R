new_product <- function(
  id,
  contract,
  version,
  code_version,
  automatic_version,
  owner = NULL,
  description = NULL
) {
  asset_id(id)
  scalar(version, "version")
  if (!is.null(owner)) {
    scalar(owner, "owner")
  }
  if (!is.null(description)) {
    scalar(description, "description")
  }
  if (!is.null(code_version)) {
    scalar(code_version, "code_version")
  }
  out <- structure(
    list(
      id = id,
      version = version,
      automatic_version = automatic_version,
      code_version = code_version,
      sources = list(),
      transforms = list(),
      contract = NULL,
      quality = list(),
      target = NULL,
      catalogs = list(),
      owner = owner,
      description = description
    ),
    class = "tw_product"
  )
  if (!is.null(contract)) {
    out <- tw_add_contract(out, contract)
  }
  out
}

editable_product <- function(x) {
  if (!inherits(x, "tw_product")) {
    abort("Start with tw_product('name') to compose a product with add_*().")
  }
  attr(x, "tw_validated") <- NULL
  x
}

#' Bind a source to a product or workflow
#'
#' Store a named primary input without reading it. A workflow can instead bind
#' one delivery with `data =` at execution. For several primary sources, use a
#' transformation that combines their named list before table operations.
#' @param x A [tw_product()] or modular [tw_workflow()] definition.
#' @param source Data frame, file path, function or source adapter.
#' @param name Optional source name, generated when omitted.
#' @param reader Optional file reader. CSV, TSV, RDS and Excel have defaults.
#' @param replace Replace a source with the same name explicitly.
#' @returns An updated definition. No source data are read.
#' @seealso [tw_replace_sources()], [tw_source_database()], [tw_trial()]
#' @export
#' @examples
#' flow <- tw_workflow() |>
#'   tw_add_product(tw_product("orders")) |>
#'   tw_add_source(data.frame(id = 1:2, amount = c(25, 75)), name = "orders")
#' tw_collect(tw_trial(flow))
tw_add_source <- function(
  x,
  source,
  name = NULL,
  reader = NULL,
  replace = FALSE
) {
  if (inherits(x, "tw_product_workflow")) {
    holder <- tw_product("workflow")
    holder$sources <- x$sources
    holder <- tw_add_source(holder, source, name, reader, replace)
    x$sources <- holder$sources
    check_workflow_slots(x)
    return(x)
  }
  x <- editable_product(x)
  flag(replace, "replace")
  if (is.null(name) && replace) {
    if (length(x$sources) != 1L) {
      abort(
        "Name the source to replace when the product does not have exactly one primary source."
      )
    }
    name <- names(x$sources)[[1]]
  }
  name <- name %||%
    if (inherits(source, "tw_product")) {
      source$id
    } else {
      paste0("source_", length(x$sources) + 1L)
    }
  scalar(name, "name")
  if (name %in% names(x$sources) && !replace) {
    abort(paste0(
      "Source `",
      name,
      "` already exists. Use replace = TRUE to replace it."
    ))
  }
  x$sources[[name]] <- normalize_source(source, x$id, name, reader)
  x
}

normalize_source <- function(source, id, name, reader = NULL) {
  if (inherits(source, "tw_product_workflow")) {
    source <- compile_product_workflow(source)
  }
  if (!is.null(reader) && (!is.character(source) || !is.function(reader))) {
    abort("reader is only used with a file path and must be a function.")
  }
  if (inherits(source, "tw_run_result")) {
    source <- normalize_result_source(source)
  }
  if (is.character(source)) {
    scalar(source, "source path")
    if (
      is.null(reader) &&
        tolower(tools::file_ext(source)) %in% c("parquet", "pq")
    ) {
      source <- tw_source_parquet(source)
    } else {
      source <- tw_source_file(
        paste0(
          id,
          ".source.",
          substr(digest::digest(name, algo = "sha256"), 1L, 12L)
        ),
        source,
        reader = reader %||% simple_reader(source)
      )
    }
  }
  if (!component_method("tw_read_source", source)) {
    abort(
      "source must be a table, path, function, product, successful run or source adapter."
    )
  }
  source
}
#' Add a transformation directly to a product
#'
#' For modular workflows, prefer [tw_recipe()] with [tw_step_transform()]. This
#' direct interface appends preparation to a product for compact pipelines.
#' @param x A table product definition.
#' @param transform R function, formula using `.x`, or transform adapter.
#' @param name Optional unique step name, generated when omitted.
#' @returns An updated product definition. Execution remains deferred.
#' @export
#' @examples
#' tw_product("orders", data.frame(amount = c(10, 20))) |>
#'   tw_add_transform(~ dplyr::mutate(.x, amount = amount * 2)) |>
#'   tw_trial() |>
#'   tw_collect()
tw_add_transform <- function(x, transform, name = NULL) {
  if (inherits(x, "tw_model_product")) {
    abort(
      "Transform a member table product, then use tw_replace_sources(model, table_name = product)."
    )
  }
  x <- editable_product(x)
  if (inherits(transform, "formula")) {
    transform <- rlang::as_function(transform)
  }
  if (!component_method("tw_execute_transform", transform)) {
    abort(
      "transform must be a function, formula using .x, or transform adapter."
    )
  }
  name <- name %||% paste0("transform_", length(x$transforms) + 1L)
  scalar(name, "name")
  if (name %in% names(x$transforms)) {
    abort("Transformation names must be unique.")
  }
  x$transforms[[name]] <- transform
  x
}
#' Attach output requirements to a product specification
#'
#' The contract describes shape and keys; quality rules describe acceptable
#' values. Checks apply after preparation and gate framework writers.
#' Adding a contract replaces the previous contract. Quality rules accumulate.
#' @param x A [tw_product()] specification.
#' @param contract Contract, named type vector, or named list of prototypes.
#' @param quality One-sided row predicate, function, rule, or list of rules.
#'   Formula `NA` results count as failures. Functions return scalar logicals
#'   or [tw_quality_counts()]. Names in rule lists become rule names.
#' @param name Optional quality rule name.
#' @returns An updated product specification, without executing checks.
#' @seealso [tw_contract()], [tw_quality_rule()], [tw_set_engine()]
#' @export
#' @examples
#' tw_product("orders") |>
#'   tw_add_contract(c(id = "integer", amount = "numeric")) |>
#'   tw_add_quality(~ amount >= 0)
tw_add_contract <- function(x, contract) {
  x <- editable_product(x)
  if (!inherits(contract, "tw_contract")) {
    contract <- tw_contract(paste0(x$id, ".contract"), columns = contract)
  }
  if (isTRUE(attr(contract, "tw_anonymous"))) {
    contract$id <- paste0(x$id, ".contract")
    attr(contract, "tw_anonymous") <- NULL
  }
  assert_contract_ready(contract)
  x$contract <- contract
  x
}
#' @rdname tw_add_contract
#' @param engine Optional formula quality engine, `"native"` or
#'   `"pointblank"`. Omit to preserve engines on existing rule specifications.
#' @export
tw_add_quality <- function(x, quality, name = NULL, engine = NULL) {
  x <- editable_product(x)
  x$quality <- normalize_quality_rules(
    quality,
    name,
    engine,
    existing = x$quality
  )
  x
}

#' Set a publication destination
#'
#' Store or replace a destination without writing data. [tw_trial()] disables
#' it; [tw_run()] and [tw_publish()] execute it after successful output checks.
#' @param x A [tw_product()] or modular [tw_workflow()] definition.
#' @param target Lake folder path, connected lake, configuration or target
#'   adapter. Use [tw_target_lake()] for partition or layer options.
#' @returns An updated definition.
#' @export
#' @examples
#' tw_workflow() |>
#'   tw_add_product(tw_product("orders")) |>
#'   tw_set_target("data/orders")
tw_set_target <- function(x, target) {
  if (inherits(x, "tw_product_workflow")) {
    x$target <- normalize_target(target)
    check_workflow_slots(x)
    return(x)
  }
  x <- editable_product(x)
  x$target <- normalize_target(target)
  x
}
#' Attach a metadata destination to a product
#'
#' Catalog callbacks receive descriptive run metadata after execution. Delivery
#' is outside the data transaction; retryable failures retain run evidence.
#' @param x A [tw_product()] definition.
#' @param catalog Function receiving run metadata, or catalog adapter.
#' @param name Optional unique catalog name, generated when omitted.
#' @returns An updated product definition.
#' @seealso [tw_catalog_openlineage()], [tw_retry_catalogs()]
#' @export
#' @examples
#' tw_product("orders") |>
#'   tw_add_catalog(function(metadata) invisible(metadata), name = "audit")
tw_add_catalog <- function(x, catalog, name = NULL) {
  x <- editable_product(x)
  if (!component_method("tw_publish_metadata", catalog)) {
    abort(
      "catalog must be a function or an adapter with tw_publish_metadata()."
    )
  }
  name <- name %||%
    if (is.function(catalog)) {
      paste0("callback-", length(x$catalogs) + 1L)
    } else {
      catalog$id %||% paste0("catalog-", length(x$catalogs) + 1L)
    }
  scalar(name, "name")
  if (name %in% names(x$catalogs)) {
    abort("Catalog names must be unique.")
  }
  x$catalogs[[name]] <- catalog
  x
}

#' @export
tw_validate.tw_product <- function(data, contract = NULL, ...) {
  rlang::check_dots_empty()
  if (!is.null(contract)) {
    abort("Add a contract with tw_add_contract() before preflight.")
  }
  validate_product_graph(data)
  attr(data, "tw_validated") <- TRUE
  data
}

validate_product_graph <- function(product) {
  seen <- new.env(parent = emptyenv())
  visit <- function(data, stack = character()) {
    asset_id(data$id)
    scalar(data$version, "version")
    if (data$id %in% stack) {
      abort(
        paste0(
          "Product dependency cycle: ",
          paste(c(stack, data$id), collapse = " -> "),
          "."
        ),
        "tw_dependency_cycle"
      )
    }
    if (exists(data$id, seen, inherits = FALSE)) {
      previous <- get(data$id, seen, inherits = FALSE)
      attr(previous, "tw_validated") <- NULL
      current <- data
      attr(current, "tw_validated") <- NULL
      if (!identical(previous, current)) {
        abort(
          paste0(
            "Different definitions use product id `",
            data$id,
            "`. Give each product a unique id."
          ),
          "tw_dependency_conflict"
        )
      }
      return(invisible(NULL))
    }
    if (!length(data$sources)) {
      abort("This product has no source. Add one with tw_add_source().")
    }
    if (
      is.null(names(data$sources)) ||
        anyDuplicated(names(data$sources)) ||
        anyNA(names(data$sources)) ||
        any(!nzchar(names(data$sources)))
    ) {
      abort("Product sources must have unique, non-empty names.")
    }
    for (source in product_sources(data)) {
      if (inherits(source, "tw_product")) {
        visit(source, c(stack, data$id))
      } else {
        assert_component(source, "tw_read_source")
      }
    }
    for (step in data$transforms) {
      assert_component(step, "tw_execute_transform")
    }
    if (!is.null(data$contract)) {
      assert_contract_ready(data$contract)
      args <- data$contract
      args[c("kind", "automatic_schema")] <- NULL
      args$columns <- unlist(args$columns, use.names = TRUE)
      do.call(tw_contract, args)
    }
    rules <- c(data$contract$rules, data$quality)
    if (anyDuplicated(vapply(rules, `[[`, character(1), "name"))) {
      abort("Contract and added quality rules must have unique names.")
    }
    for (rule in rules) {
      assert_component(rule, "tw_run_quality")
    }
    if (!is.null(data$target)) {
      tw_check_component(data$target)
      if (
        !component_method("tw_execute_target", data$target) &&
          !component_method("tw_write_target", data$target)
      ) {
        abort("The target needs a tw_write_target() method.")
      }
    }
    normalize_catalogs(data$catalogs)
    for (catalog in data$catalogs) {
      assert_component(catalog, "tw_publish_metadata")
    }
    assign(data$id, data, seen)
    invisible(NULL)
  }
  visit(product)
  invisible(product)
}

#' Inspect a product or run without executing it
#'
#' Product inspection includes identity, source description, ordered steps,
#' contract, target and optional integrations. Data rows, connection credentials
#' and closure environments are omitted. This is descriptive metadata, not a
#' portable executable serialization. Save project R code for reproducibility.
#' Extension packages may implement `tw_inspect()` to provide safe descriptors.
#' @param x Product, run or component.
#' @param ... Reserved for extensions.
#' @returns `tw_inspect()` returns a list. `tw_explain()` returns a character
#'   vector invisibly after printing a plain-language explanation.
#' @export
#' @examples
#' orders <- tw_product("orders") |> tw_add_source(data.frame(id = 1:2))
#' tw_inspect(orders)
#' tw_explain(orders)
tw_inspect <- function(x, ...) UseMethod("tw_inspect")
#' @export
tw_inspect.default <- function(x, ...) list(type = class(x)[[1]])
#' @export
tw_inspect.NULL <- function(x, ...) list(type = "memory")
#' @export
tw_inspect.data.frame <- function(x, ...) {
  list(type = "data.frame", rows = nrow(x), columns = names(x))
}
#' @export
tw_inspect.function <- function(x, ...) {
  list(type = "R function", code = canonical(x))
}
#' @export
tw_inspect.tw_source <- function(x, ...) {
  list(type = "file", id = x$id, path = x$path, reader = canonical(x$reader))
}
#' @export
tw_inspect.tw_database_source <- function(x, ...) {
  list(
    type = "DBI",
    table = if (inherits(x$table, "Id")) as.list(x$table@name) else x$table,
    query = x$query,
    parameter_names = names(x$params),
    connection = if (is.function(x$connection)) "factory" else "caller-owned"
  )
}
#' @export
tw_inspect.tw_sql_transform <- function(x, ...) {
  list(type = "DuckDB SQL", query = x$query)
}
#' @export
tw_inspect.tw_product <- function(x, ...) {
  sources <- lapply(x$sources, function(source) {
    if (inherits(source, "tw_product")) {
      list(type = "product", id = source$id, version = source$version)
    } else {
      tw_inspect(source)
    }
  })
  list(
    id = x$id,
    version = x$version,
    code_version = x$code_version,
    status = if (isTRUE(attr(x, "tw_validated"))) "validated" else "defined",
    sources = sources,
    transforms = lapply(x$transforms, tw_inspect),
    contract = canonical(effective_product_contract(x)),
    quality = canonical(x$quality),
    target = tw_inspect(x$target),
    catalogs = lapply(x$catalogs, tw_inspect),
    owner = x$owner %||% x$contract$owner %||% "",
    description = x$description %||% x$contract$description %||% "",
    plan = product_plan(x, check = FALSE)
  )
}
#' @export
tw_inspect.tw_run_result <- function(x, ...) {
  x[c(
    "run_id",
    "status",
    "release_id",
    "asset",
    "started_at",
    "finished_at",
    "backend",
    "inputs",
    "outputs",
    "quality",
    "warnings",
    "metadata",
    "lifecycle"
  )]
}
#' @rdname tw_inspect
#' @importFrom dplyr explain
#' @export
tw_explain <- function(x, ...) dplyr::explain(x, ...)

#' @rdname tw_inspect
#' @export
explain.tw_product <- function(x, ...) {
  rlang::check_dots_empty()
  target <- product_display_target(x)
  text <- c(
    paste0("Product: ", x$id),
    paste0("Read: ", length(x$sources), " named source(s)."),
    paste0(
      "Deliveries: ",
      paste(names(delivery_aliases(x)), collapse = ", "),
      "."
    ),
    "Replace a delivery with sources = list(delivery_name = new_data).",
    if (length(product_sources(x)) > length(x$sources)) {
      paste0(
        "Lookups: ",
        length(product_sources(x)) - length(x$sources),
        " auxiliary source(s), acquired once before transformations."
      )
    },
    if (length(x$sources) > 1L) {
      "The first transform receives a named list; combine it into one table."
    } else {
      "Transforms receive one table, which may stay lazy."
    },
    paste0("Transform: ", length(x$transforms), " ordered step(s)."),
    paste0(
      "Check: ",
      if (is.null(x$contract)) {
        "inferred structure"
      } else {
        "declared contract"
      },
      " and ",
      length(x$quality),
      " additional rule(s)."
    ),
    if (is.null(target)) {
      "Return: checked data and run evidence. tw_collect() materializes lazy output."
    } else {
      paste0(
        "Publish: ",
        tw_inspect(target)$type,
        ". Failed checks block publication."
      )
    },
    if (identical(tw_capabilities(target)$lazy, FALSE)) {
      "Materialization: the target requires an ordinary table."
    } else {
      "Materialization: lazy tables remain lazy unless a component collects."
    },
    product_display_defaults(x),
    "tw_validate() checks configuration and dependency cycles; tw_run() executes."
  )
  cat(paste(text, collapse = "\n"), "\n")
  invisible(text)
}
#' @export
print.tw_product <- function(x, ...) {
  cat("<Data product:", x$id, ">\n")
  cat(
    "Deliveries: ",
    if (!length(delivery_aliases(x))) {
      "not set"
    } else {
      paste(names(delivery_aliases(x)), collapse = ", ")
    },
    "\n",
    sep = ""
  )
  cat("Transformations:", length(x$transforms), "\n")
  cat(
    "Contract:",
    if (is.null(x$contract)) {
      "automatic structure"
    } else {
      paste(length(x$contract$columns), "fields, version", x$contract$version)
    },
    "\n"
  )
  cat("Quality:", length(x$quality) + length(x$contract$rules), "rules\n")
  target <- product_display_target(x)
  target_label <- tw_inspect(target)$type
  if (inherits(target, "tw_lake_target")) {
    target_label <- paste0(target_label, " (", target$layer, ")")
  }
  cat("Target:", target_label, "\n")
  defaults <- product_display_defaults(x)
  if (!is.null(defaults)) {
    cat(defaults, "\n")
  }
  cat(
    "Status:",
    if (isTRUE(attr(x, "tw_validated"))) {
      "validated"
    } else {
      "defined"
    },
    "\n"
  )
  invisible(x)
}

product_display_target <- function(x) {
  execution <- attr(x, "tw_execution_config", exact = TRUE)
  target <- x$target %||% execution$to
  if (
    inherits(target, "tw_lake_target") &&
      !is.null(execution$layer) &&
      (is.null(x$target) || is.null(target$layer))
  ) {
    target$layer <- execution$layer
  }
  target
}

product_display_defaults <- function(x) {
  execution <- attr(x, "tw_execution_config", exact = TRUE)
  if (is.null(execution)) {
    return(NULL)
  }
  paste0(
    "Stored execution (root only): quality = ",
    execution$quality,
    "; relationships = ",
    execution$relationships,
    ". Override with tw_run(execution = )."
  )
}

product_plan <- function(x, check = TRUE) {
  sources <- product_sources(x)
  source_types <- vapply(
    sources,
    function(source) {
      if (inherits(source, "tw_product")) {
        "product"
      } else {
        tw_inspect(source)$type
      }
    },
    character(1)
  )
  steps <- c(
    rep("read", length(sources)),
    rep("transform", length(x$transforms)),
    "validate",
    "publish",
    rep("catalog", length(x$catalogs))
  )
  ids <- c(
    names(sources),
    names(x$transforms),
    x$contract$id %||% "automatic structure",
    x$id,
    if (length(x$catalogs)) names(normalize_catalogs(x$catalogs))
  )
  components <- c(sources, x$transforms, list(NULL, x$target), x$catalogs)
  lazy <- vapply(
    components,
    function(component) tw_capabilities(component)$lazy,
    logical(1)
  )
  out <- tibble::tibble(
    position = seq_along(steps),
    step = steps,
    id = ids,
    target = c(
      source_types,
      vapply(x$transforms, function(step) tw_inspect(step)$type, character(1)),
      "contract and quality",
      tw_inspect(x$target)$type,
      rep("metadata only", length(x$catalogs))
    ),
    materializes = ifelse(is.na(lazy), NA, !lazy)
  )
  if (check) {
    attr(out, "complete") <- tryCatch(
      {
        tw_validate(x)
        TRUE
      },
      error = function(e) FALSE
    )
  }
  out
}
