new_product <- function(
  id,
  contract,
  version,
  code_version,
  automatic_version,
  owner = "",
  description = ""
) {
  asset_id(id)
  scalar(version, "version")
  if (!is.null(code_version)) {
    scalar(code_version, "code_version")
  }
  out <- structure(
    list(
      id = id,
      version = version,
      automatic_version = automatic_version,
      code_version = code_version,
      source = NULL,
      transforms = list(),
      contract = NULL,
      quality = list(),
      target = NULL,
      catalogs = list(),
      owner = owner,
      description = description
    ),
    class = "dl_product_spec"
  )
  if (!is.null(contract)) {
    out <- dl_add_contract(out, contract)
  }
  out
}

editable_product <- function(x) {
  if (!inherits(x, "dl_product_spec")) {
    abort("Start with dl_product('name') to compose a product with dl_add_*().")
  }
  attr(x, "dl_validated") <- NULL
  x
}

#' Compose a data product using ordinary R objects
#'
#' These functions describe work without executing it. Start with
#' `dl_product("orders")`, add a data frame, file path, zero-argument function
#' or source adapter, then add only the capabilities you need.
#' Transformations run in addition order; the contract and quality checks run
#' on the final candidate. Adding a source, contract or target replaces that
#' component. Transforms, quality rules and catalogs accumulate.
#'
#' @param x Product created with `dl_product("name")`.
#' @param source Data frame, file path, function or source adapter.
#' @param reader Optional file reader. CSV, TSV, RDS and Excel have defaults.
#' @param transform R function, formula using `.x`, or transform adapter.
#' @param name Optional step name, generated when omitted.
#' @param contract Contract, named type vector, or named list of prototypes.
#' @param quality One-sided row predicate, function, rule, or list of rules.
#'   Formula `NA` results count as failures. Functions return scalar logicals
#'   or [dl_quality_counts()]. Names in rule lists become rule names.
#' @param target Lake folder path, connected lake, configuration or target
#'   adapter. Use [dl_target_lake()] for partition or layer options.
#' @param catalog Function receiving run metadata, or catalog adapter.
#' @returns An updated product specification. No source data are read.
#' @seealso [dl_run()], [dl_publish()], [dl_validate()], [dl_inspect()]
#' @export
#' @examples
#' orders <- dl_product("orders") |>
#'   dl_add_source(data.frame(id = 1:2, amount = c(25, 75))) |>
#'   dl_add_transform(function(data) transform(data, amount = amount * 2)) |>
#'   dl_add_contract(c(id = "integer", amount = "numeric")) |>
#'   dl_add_quality(~ amount >= 0)
#' orders |> dl_run() |> dl_collect()
dl_add_source <- function(x, source, reader = NULL) {
  x <- editable_product(x)
  if (!is.null(reader) && (!is.character(source) || !is.function(reader))) {
    abort("reader is only used with a file path and must be a function.")
  }
  if (is.character(source)) {
    scalar(source, "source path")
    source <- dl_source(
      paste0(x$id, ".source"),
      source,
      reader = reader %||% simple_reader(source)
    )
  }
  if (!component_method("dl_read_source", source)) {
    abort("source must be a data frame, path, function or source adapter.")
  }
  x$source <- source
  x
}
#' @rdname dl_add_source
#' @export
dl_add_transform <- function(x, transform, name = NULL) {
  x <- editable_product(x)
  if (inherits(transform, "formula")) {
    transform <- rlang::as_function(transform)
  }
  if (!component_method("dl_execute_transform", transform)) {
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
#' @rdname dl_add_source
#' @export
dl_add_contract <- function(x, contract) {
  x <- editable_product(x)
  if (!inherits(contract, "dl_contract")) {
    contract <- dl_contract(paste0(x$id, ".contract"), columns = contract)
  }
  if (isTRUE(attr(contract, "dl_anonymous"))) {
    contract$id <- paste0(x$id, ".contract")
    attr(contract, "dl_anonymous") <- NULL
  }
  assert_contract_ready(contract)
  x$contract <- contract
  x
}
#' @rdname dl_add_source
#' @export
dl_add_quality <- function(x, quality, name = NULL) {
  x <- editable_product(x)
  if (is.list(quality) && !inherits(quality, "dl_rule")) {
    if (!is.null(name)) {
      abort("Name individual rules in the quality list.")
    }
    for (i in seq_along(quality)) {
      label <- names(quality)[i]
      if (is.null(label) || is.na(label) || !nzchar(label)) {
        label <- NULL
      }
      x <- dl_add_quality(x, quality[[i]], label)
    }
    return(x)
  }
  if (!inherits(quality, "dl_rule")) {
    quality <- dl_rule(
      name %||% paste0("quality_", length(x$quality) + 1L),
      quality
    )
  } else if (!is.null(name)) {
    quality$name <- scalar(name, "name")
  }
  if (quality$name %in% vapply(x$quality, `[[`, character(1), "name")) {
    abort("Quality rule names must be unique.")
  }
  x$quality <- c(x$quality, list(quality))
  x
}
#' @rdname dl_add_source
#' @export
dl_add_target <- function(x, target) {
  x <- editable_product(x)
  x$target <- normalize_target(target)
  x
}
#' @rdname dl_add_source
#' @export
dl_add_catalog <- function(x, catalog) {
  x <- editable_product(x)
  if (!component_method("dl_publish_metadata", catalog)) {
    abort(
      "catalog must be a function or an adapter with dl_publish_metadata()."
    )
  }
  x$catalogs <- c(x$catalogs, list(catalog))
  x
}

#' @export
dl_validate.dl_product_spec <- function(data, contract = NULL, ...) {
  rlang::check_dots_empty()
  if (!is.null(contract)) {
    abort("Add a contract with dl_add_contract() before preflight.")
  }
  asset_id(data$id)
  scalar(data$version, "version")
  if (is.null(data$source)) {
    abort("This product has no source. Add one with dl_add_source().")
  }
  assert_component(data$source, "dl_read_source")
  for (step in data$transforms) {
    assert_component(step, "dl_execute_transform")
  }
  if (!is.null(data$contract)) {
    assert_contract_ready(data$contract)
    args <- data$contract
    args[c("kind", "automatic_schema")] <- NULL
    args$columns <- unlist(args$columns, use.names = TRUE)
    do.call(dl_contract, args)
  }
  rules <- c(data$contract$rules, data$quality)
  if (anyDuplicated(vapply(rules, `[[`, character(1), "name"))) {
    abort("Contract and added quality rules must have unique names.")
  }
  for (rule in rules) {
    assert_component(rule, "dl_run_quality")
  }
  if (!is.null(data$target)) {
    dl_check_component(data$target)
    if (
      !component_method("dl_execute_target", data$target) &&
        !component_method("dl_write_target", data$target)
    ) {
      abort("The target needs dl_write_target() or dl_execute_target().")
    }
  }
  for (catalog in data$catalogs) {
    assert_component(catalog, "dl_publish_metadata")
  }
  attr(data, "dl_validated") <- TRUE
  data
}

#' Inspect a product or run without executing it
#'
#' Product inspection includes identity, source description, ordered steps,
#' contract, target and optional integrations. Data rows, connection credentials
#' and closure environments are omitted. This is descriptive metadata, not a
#' portable executable serialization. Save project R code for reproducibility.
#' Extension packages may implement `dl_inspect()` to provide safe descriptors.
#' @param x Product, run or component.
#' @param ... Reserved for extensions.
#' @returns `dl_inspect()` returns a list. `dl_explain()` returns a character
#'   vector invisibly after printing a plain-language explanation.
#' @export
#' @examples
#' orders <- dl_product("orders") |> dl_add_source(data.frame(id = 1:2))
#' dl_inspect(orders)
#' dl_explain(orders)
dl_inspect <- function(x, ...) UseMethod("dl_inspect")
#' @export
dl_inspect.default <- function(x, ...) list(type = class(x)[[1]])
#' @export
dl_inspect.NULL <- function(x, ...) list(type = "memory")
#' @export
dl_inspect.data.frame <- function(x, ...) {
  list(type = "data.frame", rows = nrow(x), columns = names(x))
}
#' @export
dl_inspect.function <- function(x, ...) {
  list(type = "R function", code = canonical(x))
}
#' @export
dl_inspect.dl_source <- function(x, ...) {
  list(type = "file", id = x$id, path = x$path, reader = canonical(x$reader))
}
#' @export
dl_inspect.dl_database_source <- function(x, ...) {
  list(
    type = "DBI",
    table = if (inherits(x$table, "Id")) as.list(x$table@name) else x$table,
    query = x$query,
    parameter_names = names(x$params),
    connection = if (is.function(x$connection)) "factory" else "caller-owned"
  )
}
#' @export
dl_inspect.dl_sql_transform <- function(x, ...) {
  list(type = "DuckDB SQL", query = x$query)
}
#' @export
dl_inspect.dl_product_spec <- function(x, ...) {
  list(
    id = x$id,
    version = x$version,
    code_version = x$code_version,
    status = if (isTRUE(attr(x, "dl_validated"))) "validated" else "defined",
    source = if (is.null(x$source)) {
      list(type = "missing")
    } else {
      dl_inspect(x$source)
    },
    transforms = lapply(x$transforms, dl_inspect),
    contract = canonical(x$contract),
    quality = canonical(x$quality),
    target = dl_inspect(x$target),
    catalogs = lapply(x$catalogs, dl_inspect),
    owner = x$owner %||% x$contract$owner,
    description = x$description %||% x$contract$description
  )
}
#' @export
dl_inspect.dl_run_result <- function(x, ...) {
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
#' @rdname dl_inspect
#' @export
dl_explain <- function(x) {
  if (!inherits(x, "dl_product_spec")) {
    abort("Use a composed dl_product() with dl_explain().")
  }
  text <- c(
    paste0("Product: ", x$id),
    paste0(
      "Read: ",
      if (is.null(x$source)) "add a source first" else dl_inspect(x$source)$type
    ),
    paste0(
      "Transform: ",
      length(x$transforms),
      " ordered step(s), using ordinary R tables."
    ),
    paste0(
      "Check: ",
      if (is.null(x$contract)) "inferred structure" else "declared contract",
      " and ",
      length(x$quality),
      " additional quality rule(s)."
    ),
    if (is.null(x$target)) {
      "Return: data and run evidence in memory. Use dl_publish() for durable storage."
    } else {
      paste0(
        "Publish: ",
        dl_inspect(x$target)$type,
        ". Failed checks block publication."
      )
    },
    "dl_validate() checks configuration; dl_run() executes the work."
  )
  cat(paste(text, collapse = "\n"), "\n")
  invisible(text)
}
#' @export
print.dl_product_spec <- function(x, ...) {
  cat("<Data product:", x$id, ">\n")
  cat(
    "Source:",
    if (is.null(x$source)) "not set" else dl_inspect(x$source)$type,
    "\n"
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
  cat("Target:", dl_inspect(x$target)$type, "\n")
  cat(
    "Status:",
    if (isTRUE(attr(x, "dl_validated"))) "validated" else "defined",
    "\n"
  )
  invisible(x)
}

product_plan <- function(x) {
  steps <- c(
    "read",
    rep("transform", length(x$transforms)),
    "validate",
    "publish",
    rep("catalog", length(x$catalogs))
  )
  ids <- c(
    x$id,
    names(x$transforms),
    x$contract$id %||% "automatic structure",
    x$id,
    if (length(x$catalogs)) {
      paste0("catalog_", seq_along(x$catalogs))
    } else {
      character()
    }
  )
  out <- tibble::tibble(
    position = seq_along(steps),
    step = steps,
    id = ids,
    target = c(
      if (is.null(x$source)) "missing source" else dl_inspect(x$source)$type,
      vapply(x$transforms, function(step) dl_inspect(step)$type, character(1)),
      "contract and quality",
      dl_inspect(x$target)$type,
      rep("metadata only", length(x$catalogs))
    )
  )
  attr(out, "complete") <- tryCatch(
    {
      dl_validate(x)
      TRUE
    },
    error = function(e) FALSE
  )
  out
}
