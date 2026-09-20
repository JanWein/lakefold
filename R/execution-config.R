#' Reuse explicit execution defaults
#'
#' Define execution choices once and pass the value to [run()], [publish()] or
#' [ingest()]. Construction neither reads sources nor opens destinations.
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
      x$contract$rules <- lapply(x$contract$rules, resolve_rule)
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
