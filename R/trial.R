#' Try a product without invoking configured writers
#'
#' Executes the product's sources, transformations and checks, with targets,
#' catalogs and durable run evidence disabled throughout its dependency graph.
#' The original definition is unchanged. Source and transformation callbacks are
#' ordinary user code: their own side effects cannot be prevented by the framework.
#' Read-only access to existing published inputs is still allowed.
#' @param x Product definition.
#' @param data,sources Replacement delivery or named sources, as in [run()].
#' @param stop_on_failure Signal an error on a failed check. Use `FALSE` to
#'   inspect the returned result.
#' @returns An in-memory run result accepted by [collect()] and [measure()].
#' @export
#' @examples
#' orders <- product("orders", data.frame(amount = c(10, 20))) |>
#'   set_target("reporting-lake")
#' trial(orders) |> collect()
trial <- function(x, data = NULL, sources = NULL, stop_on_failure = TRUE) {
  if (!inherits(x, "tw_product")) {
    abort("trial() needs a product definition.")
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
  run(clear(x), evidence = NULL, stop_on_failure = stop_on_failure)
}
