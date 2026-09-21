#' Inspect adapter capabilities
#'
#' Adapters report the same six logical fields. `TRUE` means supported, `FALSE`
#' means unsupported, and `NA` means undeclared or dependent on user code.
#' Capabilities describe behavior; they do not test remote permissions.
#' Extension methods can use [tw_component_capabilities()] for a stable shape.
#' An ordinary function may support lazy tables, but its body is not inspected.
#' @param x Source, transform, target or connected lake.
#' @param ... Reserved for adapter options.
#' @returns A named list of logical capabilities.
#' @export
#' @examples
#' tw_capabilities(data.frame(id = 1L))
#' tw_capabilities(NULL)
tw_capabilities <- function(x, ...) UseMethod("tw_capabilities")

#' @rdname tw_capabilities
#' @param read,write,lazy,transactions,partition,immutable Logical scalars.
#' @export
tw_component_capabilities <- function(
  read = NA,
  write = NA,
  lazy = NA,
  transactions = NA,
  partition = NA,
  immutable = NA
) {
  values <- list(
    read = read,
    write = write,
    lazy = lazy,
    transactions = transactions,
    partition = partition,
    immutable = immutable
  )
  if (
    !all(vapply(
      values,
      function(value) is.logical(value) && length(value) == 1L,
      logical(1)
    ))
  ) {
    abort("Each capability must be TRUE, FALSE or NA.")
  }
  values
}
#' @export
tw_capabilities.default <- function(x, ...) tw_component_capabilities()
#' @export
tw_capabilities.NULL <- function(x, ...) {
  tw_component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = TRUE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
tw_capabilities.data.frame <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
tw_capabilities.function <- function(x, ...) {
  tw_component_capabilities(read = TRUE, write = FALSE)
}
#' @export
tw_capabilities.tbl_sql <- function(x, ...) {
  tw_component_capabilities(read = TRUE, write = FALSE, lazy = TRUE)
}
#' @export
tw_capabilities.tw_source <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
tw_capabilities.tw_database_source <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = x$lazy,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
tw_capabilities.tw_release_source <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = inherits(x$lake, "tw_lake"),
    transactions = TRUE,
    partition = FALSE,
    immutable = TRUE
  )
}
#' @export
tw_capabilities.tw_result_source <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = is_lazy_table(x$data),
    immutable = FALSE
  )
}
#' @export
tw_capabilities.tw_product <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = !is.null(x$target),
    lazy = tw_capabilities(x$target)$lazy
  )
}
#' @export
tw_capabilities.tw_lake_target <- function(x, ...) {
  tw_component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = TRUE,
    partition = TRUE,
    immutable = TRUE
  )
}
#' @export
tw_capabilities.tw_lake <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = !isTRUE(x$config$read_only),
    lazy = TRUE,
    transactions = TRUE,
    partition = TRUE,
    immutable = TRUE
  )
}
#' @export
tw_capabilities.tw_sql_transform <- function(x, ...) {
  tw_component_capabilities(
    read = FALSE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
