#' Try a product without invoking configured writers
#'
#' Executes the product's sources, transformations and checks, with targets,
#' catalogs and durable run evidence disabled throughout its dependency graph.
#' The original definition is unchanged. Source and transformation callbacks are
#' ordinary user code: their own side effects cannot be prevented by the framework.
#' Read-only access to existing published inputs is still allowed.
#' @param x Product or modular [tw_workflow()] definition.
#' @param data,sources Replacement delivery or named sources, as in [tw_run()].
#' @param stop_on_failure Defaults to `FALSE`: a failed trial returns a result
#'   for [tw_quality_report()] and [tw_quality_rows()]. Use `TRUE` to raise an error.
#'   [tw_run()] and [tw_publish()] still raise errors on failure by default.
#' @returns An in-memory run result accepted by [tw_collect()] and [tw_measure()].
#' @export
#' @examples
#' orders <- tw_product("orders", data.frame(amount = c(10, 20))) |>
#'   tw_set_target("reporting-lake")
#' tw_trial(orders) |> tw_collect()
tw_trial <- function(x, data = NULL, sources = NULL, stop_on_failure = FALSE) {
  if (inherits(x, "tw_product_workflow")) {
    return(tw_trial(
      compile_product_workflow(x, data, sources),
      stop_on_failure = stop_on_failure
    ))
  }
  if (!inherits(x, "tw_product")) {
    abort("tw_trial() needs a product definition.")
  }
  if (inherits(x, "tw_model_product")) {
    x <- apply_execution_defaults(x, product_execution(x, NULL))
    x$target <- NULL
    attr(x, "tw_execution_config") <- NULL
    return(tw_run(
      x,
      data = data,
      sources = sources,
      stop_on_failure = stop_on_failure
    ))
  }
  x <- replace_execution_sources(x, data, sources)
  x <- apply_execution_defaults(x, product_execution(x, NULL))
  clear <- function(product) {
    product$target <- NULL
    product$catalogs <- list()
    attr(product, "tw_execution_config") <- NULL
    sources <- lapply(product_sources(product), function(source) {
      if (inherits(source, "tw_product")) clear(source) else source
    })
    replace_product_sources(product, sources)
  }
  tw_run(clear(x), evidence = NULL, stop_on_failure = stop_on_failure)
}
