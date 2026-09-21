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
    out <- add_contract(out, contract)
  }
  out
}

editable_product <- function(x) {
  if (!inherits(x, "tw_product")) {
    abort("Start with product('name') to compose a product with add_*().")
  }
  attr(x, "tw_validated") <- NULL
  x
}

#' Compose a data product using ordinary R objects
#'
#' These functions describe work without executing it. Start with
#' `product("orders", data)`, then add only the capabilities you need.
#' Sources can be tables, file paths, functions or source adapters.
#' Transformations run in addition order; the contract and quality checks run
#' on the final candidate. Sources, transforms, rules and catalogs accumulate.
#' A contract or target replaces the previously configured component.
#'
#' @param x Product created with `product("name")`. `add_source()` and
#'   `set_target()` also accept modular [workflow()] definitions.
#' @param source Data frame, file path, function or source adapter.
#' @param replace Replace a source with the same name explicitly.
#' @param reader Optional file reader. CSV, TSV, RDS and Excel have defaults.
#' @param transform R function, formula using `.x`, or transform adapter.
#' @param name Optional source, step or catalog name, generated when omitted.
#' @param contract Contract, named type vector, or named list of prototypes.
#' @param quality One-sided row predicate, function, rule, or list of rules.
#'   Formula `NA` results count as failures. Functions return scalar logicals
#'   or [quality_counts()]. Names in rule lists become rule names.
#' @param target Lake folder path, connected lake, configuration or target
#'   adapter. Use [target_lake()] for partition or layer options.
#' @param catalog Function receiving run metadata, or catalog adapter.
#' @returns An updated product specification. No source data are read.
#' @seealso [trial()], [run()], [publish()], [validate()], [inspect()]
#' @export
#' @examples
#' orders <- product("orders") |>
#'   add_source(data.frame(id = 1:2, amount = c(25, 75))) |>
#'   add_transform(function(data) transform(data, amount = amount * 2)) |>
#'   add_contract(c(id = "integer", amount = "numeric")) |>
#'   add_quality(~ amount >= 0)
#' orders |> trial() |> collect()
add_source <- function(x, source, name = NULL, reader = NULL, replace = FALSE) {
  if (inherits(x, "tw_product_workflow")) {
    holder <- product("workflow")
    holder$sources <- x$sources
    holder <- add_source(holder, source, name, reader, replace)
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
      source <- source_parquet(source)
    } else {
      source <- source_file(
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
  if (!component_method("read_source", source)) {
    abort(
      "source must be a table, path, function, product, successful run or source adapter."
    )
  }
  source
}
#' @rdname add_source
#' @export
add_transform <- function(x, transform, name = NULL) {
  if (inherits(x, "tw_model_product")) {
    abort(
      "Transform a member table product, then use replace_sources(model, table_name = product)."
    )
  }
  x <- editable_product(x)
  if (inherits(transform, "formula")) {
    transform <- rlang::as_function(transform)
  }
  if (!component_method("execute_transform", transform)) {
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
#' @rdname add_source
#' @export
add_contract <- function(x, contract) {
  x <- editable_product(x)
  if (!inherits(contract, "tw_contract")) {
    contract <- contract(paste0(x$id, ".contract"), columns = contract)
  }
  if (isTRUE(attr(contract, "tw_anonymous"))) {
    contract$id <- paste0(x$id, ".contract")
    attr(contract, "tw_anonymous") <- NULL
  }
  assert_contract_ready(contract)
  x$contract <- contract
  x
}
#' @rdname add_source
#' @param engine Optional formula quality engine, `"native"` or
#'   `"pointblank"`. Omit to preserve engines on existing rule specifications.
#' @export
add_quality <- function(x, quality, name = NULL, engine = NULL) {
  x <- editable_product(x)
  x$quality <- normalize_quality_rules(
    quality,
    name,
    engine,
    existing = x$quality
  )
  x
}

#' @rdname add_source
#' @export
set_target <- function(x, target) {
  if (inherits(x, "tw_product_workflow")) {
    x$target <- normalize_target(target)
    check_workflow_slots(x)
    return(x)
  }
  x <- editable_product(x)
  x$target <- normalize_target(target)
  x
}
#' @rdname add_source
#' @export
add_catalog <- function(x, catalog, name = NULL) {
  x <- editable_product(x)
  if (!component_method("publish_metadata", catalog)) {
    abort(
      "catalog must be a function or an adapter with publish_metadata()."
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
validate.tw_product <- function(data, contract = NULL, ...) {
  rlang::check_dots_empty()
  if (!is.null(contract)) {
    abort("Add a contract with add_contract() before preflight.")
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
      abort("This product has no source. Add one with add_source().")
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
        assert_component(source, "read_source")
      }
    }
    for (step in data$transforms) {
      assert_component(step, "execute_transform")
    }
    if (!is.null(data$contract)) {
      assert_contract_ready(data$contract)
      args <- data$contract
      args[c("kind", "automatic_schema")] <- NULL
      args$columns <- unlist(args$columns, use.names = TRUE)
      do.call(contract, args)
    }
    rules <- c(data$contract$rules, data$quality)
    if (anyDuplicated(vapply(rules, `[[`, character(1), "name"))) {
      abort("Contract and added quality rules must have unique names.")
    }
    for (rule in rules) {
      assert_component(rule, "run_quality")
    }
    if (!is.null(data$target)) {
      check_component(data$target)
      if (
        !component_method("tw_execute_target", data$target) &&
          !component_method("write_target", data$target)
      ) {
        abort("The target needs a write_target() method.")
      }
    }
    normalize_catalogs(data$catalogs)
    for (catalog in data$catalogs) {
      assert_component(catalog, "publish_metadata")
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
#' Extension packages may implement `inspect()` to provide safe descriptors.
#' @param x Product, run or component.
#' @param ... Reserved for extensions.
#' @returns `inspect()` returns a list. `explain()` returns a character
#'   vector invisibly after printing a plain-language explanation.
#' @export
#' @examples
#' orders <- product("orders") |> add_source(data.frame(id = 1:2))
#' inspect(orders)
#' explain(orders)
inspect <- function(x, ...) UseMethod("inspect")
#' @export
inspect.default <- function(x, ...) list(type = class(x)[[1]])
#' @export
inspect.NULL <- function(x, ...) list(type = "memory")
#' @export
inspect.data.frame <- function(x, ...) {
  list(type = "data.frame", rows = nrow(x), columns = names(x))
}
#' @export
inspect.function <- function(x, ...) {
  list(type = "R function", code = canonical(x))
}
#' @export
inspect.tw_source <- function(x, ...) {
  list(type = "file", id = x$id, path = x$path, reader = canonical(x$reader))
}
#' @export
inspect.tw_database_source <- function(x, ...) {
  list(
    type = "DBI",
    table = if (inherits(x$table, "Id")) as.list(x$table@name) else x$table,
    query = x$query,
    parameter_names = names(x$params),
    connection = if (is.function(x$connection)) "factory" else "caller-owned"
  )
}
#' @export
inspect.tw_sql_transform <- function(x, ...) {
  list(type = "DuckDB SQL", query = x$query)
}
#' @export
inspect.tw_product <- function(x, ...) {
  sources <- lapply(x$sources, function(source) {
    if (inherits(source, "tw_product")) {
      list(type = "product", id = source$id, version = source$version)
    } else {
      inspect(source)
    }
  })
  list(
    id = x$id,
    version = x$version,
    code_version = x$code_version,
    status = if (isTRUE(attr(x, "tw_validated"))) "validated" else "defined",
    sources = sources,
    transforms = lapply(x$transforms, inspect),
    contract = canonical(effective_product_contract(x)),
    quality = canonical(x$quality),
    target = inspect(x$target),
    catalogs = lapply(x$catalogs, inspect),
    owner = x$owner %||% x$contract$owner %||% "",
    description = x$description %||% x$contract$description %||% "",
    plan = product_plan(x, check = FALSE)
  )
}
#' @export
inspect.tw_run_result <- function(x, ...) {
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
#' @rdname inspect
#' @importFrom dplyr explain
#' @export
dplyr::explain

#' @rdname inspect
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
      "Return: checked data and run evidence. collect() materializes lazy output."
    } else {
      paste0(
        "Publish: ",
        inspect(target)$type,
        ". Failed checks block publication."
      )
    },
    if (identical(capabilities(target)$lazy, FALSE)) {
      "Materialization: the target requires an ordinary table."
    } else {
      "Materialization: lazy tables remain lazy unless a component collects."
    },
    product_display_defaults(x),
    "validate() checks configuration and dependency cycles; run() executes."
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
  target_label <- inspect(target)$type
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
    ". Override with run(execution = )."
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
        inspect(source)$type
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
    function(component) capabilities(component)$lazy,
    logical(1)
  )
  out <- tibble::tibble(
    position = seq_along(steps),
    step = steps,
    id = ids,
    target = c(
      source_types,
      vapply(x$transforms, function(step) inspect(step)$type, character(1)),
      "contract and quality",
      inspect(x$target)$type,
      rep("metadata only", length(x$catalogs))
    ),
    materializes = ifelse(is.na(lazy), NA, !lazy)
  )
  if (check) {
    attr(out, "complete") <- tryCatch(
      {
        validate(x)
        TRUE
      },
      error = function(e) FALSE
    )
  }
  out
}
