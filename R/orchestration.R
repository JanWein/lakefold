#' Execute product dependencies with targets
#'
#' Converts one product, or a named list of products, into ordinary targets
#' targets. Nested product sources become explicit upstream dependencies.
#' File sources get separate `format = "file"` targets so changes invalidate
#' downstream products. Constructing the graph never runs a product.
#'
#' Place `as_targets(...)` at the end of `_targets.R`, then use
#' `targets::tar_make()`. targets owns caching, dependency scheduling and
#' parallelism.
#' Each product is run once in the graph; downstream products use its completed
#' output. Product IDs must identify one definition throughout the graph.
#'
#' Only local file changes are inferred automatically. For APIs, databases and
#' other externally changing sources, provide an appropriate `cue`, commonly
#' `targets::tar_cue(mode = "always")`. Use connection factories; open DBI
#' connections and lazy tables cannot be safely stored in a targets cache.
#' A cached product does not create new run evidence until it executes again.
#' Function bodies and captured values are part of the embedded specification;
#' source project code from `_targets.R` to rebuild definitions when it changes.
#' Static references to ordinary captured values are tracked. Dynamic lookups
#' and mutable environment state need an explicit cue, just like remote data.
#' Give definition variables names such as `orders_definition` when the target
#' is named `orders`, to avoid targets' global-object name collision warning.
#' @param x Product or named list of products. Nested products are included.
#' @param cue Optional [targets::tar_cue()] applied to product targets.
#' @param evidence Optional directory for [run()] evidence.
#' @returns A list of objects from [targets::tar_target_raw()]. Product target
#'   names are derived from product IDs with `make.names()`; conflicting names
#'   are rejected. Collect a stored result with `collect(targets::tar_read(id))`.
#' @seealso [init_project()], [run()]
#' @export
#' @examplesIf requireNamespace("targets", quietly = TRUE)
#' orders <- product("orders") |> add_source(data.frame(id = 1:2))
#' as_targets(orders)
as_targets <- function(x, cue = NULL, evidence = NULL) {
  need("targets")
  if (inherits(x, "tw_product")) {
    x <- list(x)
  }
  if (
    !is.list(x) ||
      !length(x) ||
      !all(vapply(x, inherits, logical(1), "tw_product"))
  ) {
    abort("Supply a product or a non-empty list of products to as_targets().")
  }
  if (!is.null(evidence)) {
    evidence <- absolute_path(evidence)
  }
  # Each target executes independently. Resolve root defaults before separating
  # dependencies, and do not reactivate their stored root-only destinations.
  clear_defaults <- function(product) {
    attr(product, "tw_execution_config") <- NULL
    sources <- lapply(product_sources(product), function(source) {
      if (inherits(source, "tw_product")) clear_defaults(source) else source
    })
    replace_product_sources(product, sources)
  }
  x <- lapply(x, function(product) {
    clear_defaults(apply_execution_defaults(
      product,
      product_execution(product, NULL)
    ))
  })
  products <- list()
  visit <- function(product, stack = character()) {
    if (product$id %in% stack) {
      abort(paste(
        "Product dependency cycle:",
        paste(c(stack, product$id), collapse = " -> ")
      ))
    }
    if (product$id %in% names(products)) {
      if (!identical(products[[product$id]], product)) {
        abort(paste("Different product definitions share the ID:", product$id))
      }
      return(invisible(NULL))
    }
    targets_serializable(product)
    for (source in product_sources(product)) {
      if (inherits(source, "tw_product")) visit(source, c(stack, product$id))
    }
    products[[product$id]] <<- product
    invisible(NULL)
  }
  invisible(lapply(x, visit))
  target_names <- stats::setNames(make.names(names(products)), names(products))
  if (anyDuplicated(unname(target_names))) {
    abort(
      "Product IDs become duplicate targets names. Rename the conflicting products."
    )
  }
  output <- list()
  used <- unname(target_names)
  for (product in products) {
    dependencies <- list()
    files <- list()
    sources <- product_sources(product)
    for (alias in names(sources)) {
      source <- sources[[alias]]
      if (inherits(source, "tw_product")) {
        dependencies[[alias]] <- as.name(target_names[[source$id]])
      } else if (
        inherits(source, c("tw_source", "tw_parquet_source")) &&
          !grepl("^[A-Za-z][A-Za-z0-9+.-]*://", source$path)
      ) {
        name <- make.names(paste0("file_", product$id, "_", alias))
        if (name %in% used) {
          abort(paste("Generated file target name conflicts:", name))
        }
        used <- c(used, name)
        output[[length(output) + 1L]] <- targets::tar_target_raw(
          name,
          command = source$path,
          format = "file"
        )
        files[[alias]] <- as.name(name)
      }
    }
    dependency_call <- as.call(c(list(as.name("list")), dependencies))
    file_call <- as.call(c(list(as.name("list")), files))
    code <- targets_product_code(product)
    command <- as.call(list(
      quote(utils::getFromNamespace("targets_run_product", "tidyweave")),
      product,
      dependency_call,
      file_call,
      evidence,
      digest::digest(code$captures, algo = "sha256")
    ))
    output[[length(output) + 1L]] <- targets::tar_target_raw(
      name = target_names[[product$id]],
      command = command,
      cue = cue %||% targets::tar_option_get("cue"),
      deps = unique(c(targets::tar_deps_raw(command), code$dependencies))
    )
  }
  output
}

targets_serializable <- function(x) {
  if (inherits(x, c("DBIConnection", "tbl_sql", "ArrowObject"))) {
    abort(
      "targets workflows need connection factories or file sources, not live connections or lazy tables."
    )
  }
  if (is.list(x)) {
    invisible(lapply(x, targets_serializable))
  }
  invisible(x)
}

targets_run_product <- function(
  product,
  dependencies,
  files,
  evidence,
  code_signature = NULL
) {
  sources <- product_sources(product)
  for (alias in names(dependencies)) {
    result <- dependencies[[alias]]
    if (
      !inherits(result, "tw_run_result") ||
        !result$status %in% c("completed", "published", "cached")
    ) {
      abort(paste("Upstream product did not complete successfully:", alias))
    }
    sources[[alias]] <- structure(
      list(
        data = result$data %||% collect(result),
        descriptor = list(
          type = "product",
          id = sources[[alias]]$id,
          version = sources[[alias]]$version
        ),
        capabilities = capabilities(sources[[alias]]),
        reference = list(
          asset = result$asset,
          run_id = result$run_id,
          release_id = result$release_id
        )
      ),
      class = "tw_completed_source"
    )
  }
  for (alias in names(files)) {
    sources[[alias]]$path <- files[[alias]]
  }
  product <- replace_product_sources(product, sources)
  result <- run(product, evidence = evidence)
  # Never serialize a live lazy-table connection into the targets store.
  if (!is.null(result$data) && !is.data.frame(result$data)) {
    result$data <- collect(result)
  }
  result$output_lake <- NULL
  result
}

targets_product_code <- function(product) {
  dependencies <- character()
  seen <- list()
  capture <- function(x, environment_names = character()) {
    if (rlang::is_quosure(x)) {
      expression <- rlang::get_expr(x)
      return(capture(
        rlang::new_function(list(), expression, rlang::get_env(x)),
        targets_environment_names(expression)
      ))
    }
    if (is.function(x)) {
      if (
        is.primitive(x) ||
          isNamespace(environment(x)) ||
          identical(environment(x), baseenv())
      ) {
        return(NULL)
      }
      if (any(vapply(seen, identical, logical(1), x))) {
        return(canonical(x))
      }
      seen[[length(seen) + 1L]] <<- x
      expression <- as.call(list(as.name("function"), formals(x), body(x)))
      names <- union(targets::tar_deps_raw(expression), environment_names)
      values <- list()
      for (name in names) {
        if (!exists(name, environment(x), inherits = TRUE)) {
          next
        }
        value <- get(name, environment(x), inherits = TRUE)
        if (is.environment(value) || typeof(value) == "externalptr") {
          next
        }
        dependencies <<- union(dependencies, name)
        targets_serializable(value)
        values[[name]] <- capture(value)
      }
      return(list(code = canonical(x), bindings = values))
    }
    if (is.list(x)) {
      return(lapply(x, capture))
    }
    if (is.environment(x) || typeof(x) == "externalptr") {
      return(NULL)
    }
    x
  }
  captures <- capture(product)
  list(dependencies = dependencies, captures = captures)
}

# Explicit, static .env references are ordinary captured values. Dynamic
# indexing still needs a caller-supplied cue; never evaluate an index here.
targets_environment_names <- function(expression) {
  if (rlang::is_missing(expression)) {
    return(character())
  }
  if (!is.call(expression)) {
    return(character())
  }
  name <- character()
  if (
    length(expression) == 3L &&
      identical(expression[[2]], as.name(".env"))
  ) {
    if (
      identical(expression[[1]], as.name("$")) && is.symbol(expression[[3]])
    ) {
      name <- as.character(expression[[3]])
    } else if (
      identical(expression[[1]], as.name("[[")) &&
        is.character(expression[[3]]) &&
        length(expression[[3]]) == 1L
    ) {
      name <- expression[[3]]
    }
  }
  unique(c(
    name,
    unlist(
      lapply(as.list(expression)[-1], targets_environment_names),
      use.names = FALSE
    )
  ))
}

#' @export
read_source.tw_completed_source <- function(source, ...) {
  data <- source$data
  attr(data, "tw_input_reference") <- source$reference
  data
}
#' @export
inspect.tw_completed_source <- function(x, ...) {
  x$descriptor
}
#' @export
check_component.tw_completed_source <- function(x, ...) invisible(x)
#' @export
capabilities.tw_completed_source <- function(x, ...) {
  x$capabilities
}
