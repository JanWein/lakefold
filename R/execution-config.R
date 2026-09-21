#' Reuse explicit execution defaults
#'
#' Define execution choices once and pass the value to [run()], [publish()] or
#' [ingest()], or store it once with `product(execution = )`. Construction
#' neither reads sources nor opens destinations. Stored defaults require
#' connection-free destinations and are used only for the root definition.
#' Engine defaults apply recursively to dependencies without changing the
#' original definitions. Explicit rule and lookup engines always win. Only
#' ordinary formula rules inherit the quality default; custom functions and
#' agent builders retain their own semantics.
#'
#' A destination fills the root product's missing target only. Dependencies
#' without targets remain in memory. Configured targets and their layers remain
#' unchanged. The layer default applies to a newly supplied root lake destination
#' or a root target with no layer. Explicit
#' `publish(to = , layer = )` arguments override the root product only.
#' Ingestion always uses the raw layer and rejects another layer default.
#' @param quality Default formula engine: `"native"` or `"pointblank"`.
#' @param relationships Default checked lookup engine: `"native"` or `"dm"`.
#' @param to Optional target adapter, lake configuration or local lake folder.
#' @param layer Optional default lake publication layer.
#' @returns An ordinary execution configuration value. No global state is changed.
#' @export
#' @examples
#' execution <- execution_config()
#' product("orders", data.frame(amount = c(10, 20))) |>
#'   add_quality(~ amount > 0) |>
#'   run(execution = execution) |>
#'   collect()
execution_config <- function(
  quality = "native",
  relationships = "native",
  to = NULL,
  layer = NULL
) {
  scalar(quality, "quality")
  scalar(relationships, "relationships")
  normalize_quality_engine(quality)
  relationships <- match.arg(relationships, c("native", "dm"))
  if (!is.null(layer)) {
    ident(layer)
  }
  if (!is.null(to)) {
    to <- normalize_target(to)
    if (!is.null(layer) && !inherits(to, "tw_lake_target")) {
      abort("An execution layer requires a lake target.")
    }
    if (
      !component_method("write_target", to) &&
        !component_method("tw_execute_target", to)
    ) {
      abort("The execution target needs a write_target() method.")
    }
  }
  structure(
    list(
      quality = quality,
      relationships = relationships,
      to = to,
      layer = layer
    ),
    class = "tw_execution_config"
  )
}

validate_execution_config <- function(execution) {
  if (is.null(execution)) {
    return(NULL)
  }
  if (
    !inherits(execution, "tw_execution_config") ||
      !identical(names(execution), c("quality", "relationships", "to", "layer"))
  ) {
    abort("execution must be an execution_config() value.")
  }
  do.call(execution_config, unclass(execution))
}

apply_execution_defaults <- function(product, execution) {
  execution <- validate_execution_config(execution)
  if (is.null(execution)) {
    return(product)
  }
  resolve_rule <- function(rule) {
    if (
      identical(class(rule), "tw_rule") &&
        inherits(rule$check, "formula") &&
        identical(rule$engine_explicit, FALSE)
    ) {
      rule$engine <- normalize_quality_engine(execution$quality)
    }
    rule
  }
  visit <- function(x, stack = character()) {
    if (x$id %in% stack) {
      abort(
        paste0(
          "Product dependency cycle: ",
          paste(c(stack, x$id), collapse = " -> "),
          "."
        ),
        "tw_dependency_cycle"
      )
    }
    x <- editable_product(x)
    x$quality <- lapply(x$quality, resolve_rule)
    if (!is.null(x$contract)) {
      rules <- lapply(x$contract$rules, resolve_rule)
      x$execution_contract_rules <- if (!identical(rules, x$contract$rules)) {
        rules
      } else {
        NULL
      }
    }
    for (name in names(x$transforms)) {
      step <- x$transforms[[name]]
      if (
        identical(class(step), "tw_lookup_transform") &&
          identical(step$engine_explicit, FALSE)
      ) {
        step$engine <- execution$relationships
        x$transforms[[name]] <- step
      }
    }
    if (!length(stack) && is.null(x$target) && !is.null(execution$to)) {
      x$target <- execution$to
      if (!is.null(execution$layer)) x$target$layer <- execution$layer
    } else if (
      !length(stack) && is.null(x$target$layer) && !is.null(execution$layer)
    ) {
      if (!inherits(x$target, "tw_lake_target")) {
        abort(
          "An execution layer requires a lake target on the root product."
        )
      }
      x$target$layer <- execution$layer
    }
    sources <- lapply(product_sources(x), function(source) {
      if (inherits(source, "tw_product")) {
        visit(source, c(stack, x$id))
      } else {
        source
      }
    })
    replace_product_sources(x, sources)
  }
  visit(product)
}

validate_stored_execution <- function(execution) {
  execution <- validate_execution_config(execution)
  has_connection <- function(x) {
    if (inherits(x, c("tw_lake", "DBIConnection"))) {
      return(TRUE)
    }
    if (is.list(x)) {
      return(any(vapply(x, has_connection, logical(1))))
    }
    FALSE
  }
  if (has_connection(execution)) {
    abort(
      "Stored execution defaults cannot contain an open connection. Use a lake_config(), folder, or connection factory."
    )
  }
  execution
}

product_execution <- function(x, execution) {
  validate_execution_config(
    execution %||% attr(x, "tw_execution_config", exact = TRUE)
  )
}

replace_execution_sources <- function(x, data = NULL, sources = NULL) {
  if (!is.null(sources) && (!is.list(sources) || is.data.frame(sources))) {
    abort(
      "sources must be a named list, for example sources = list(orders = new_orders)."
    )
  }
  if (!is.null(data)) {
    if (!inherits(x, "tw_product") || length(x$sources) != 1L) {
      abort(
        "data requires a product with exactly one primary input. Use sources = list(name = value) for named inputs."
      )
    }
    replacement_graph(x)
    leaf <- x
    while (inherits(leaf$sources[[1L]], "tw_product")) {
      leaf <- leaf$sources[[1L]]
      if (length(leaf$sources) != 1L) {
        abort(paste0(
          "Replacing a product input requires exactly one primary source at `",
          leaf$id,
          "`. Use sources = list(name = value) to select an input."
        ))
      }
    }
    # Select the deepest product globally, so references from lookup branches
    # receive the same delivery and retain one consistent definition per ID.
    name <- if (identical(leaf$id, x$id)) names(x$sources)[[1L]] else leaf$id
    if (name %in% names(sources)) {
      abort(paste0(
        "Delivery '",
        name,
        "' was supplied in both data and sources. Supply it once, not both."
      ))
    }
    sources <- c(stats::setNames(list(data), name), sources)
  }
  if (!is.null(sources)) {
    if (!is.list(sources) || is.data.frame(sources)) {
      abort(
        "sources must be a named list, for example sources = list(orders = new_orders)."
      )
    }
    x <- replace_sources_list(x, sources)
  }
  x
}
