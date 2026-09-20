#' Inspect adapter capabilities
#'
#' Adapters report the same six logical fields. `TRUE` means supported, `FALSE`
#' means unsupported, and `NA` means undeclared or dependent on user code.
#' Capabilities describe behavior; they do not test remote permissions.
#' Extension methods can use [component_capabilities()] for a stable shape.
#' An ordinary function may support lazy tables, but its body is not inspected.
#' @param x Source, transform, target or connected lake.
#' @param ... Reserved for adapter options.
#' @returns A named list of logical capabilities.
#' @export
#' @examples
#' capabilities(data.frame(id = 1L))
#' capabilities(NULL)
capabilities <- function(x, ...) UseMethod("capabilities")

#' @rdname capabilities
#' @param read,write,lazy,transactions,partition,immutable Logical scalars.
#' @export
component_capabilities <- function(
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
capabilities.default <- function(x, ...) component_capabilities()
#' @export
capabilities.NULL <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = TRUE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
capabilities.data.frame <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
capabilities.function <- function(x, ...) {
  component_capabilities(read = TRUE, write = FALSE)
}
#' @export
capabilities.tbl_sql <- function(x, ...) {
  component_capabilities(read = TRUE, write = FALSE, lazy = TRUE)
}
#' @export
capabilities.tw_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
capabilities.tw_database_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = x$lazy,
    partition = FALSE,
    immutable = FALSE
  )
}
#' @export
capabilities.tw_release_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = inherits(x$lake, "tw_lake"),
    transactions = TRUE,
    partition = FALSE,
    immutable = TRUE
  )
}
#' @export
capabilities.tw_result_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = is_lazy_table(x$data),
    immutable = FALSE
  )
}
#' @export
capabilities.tw_product <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = !is.null(x$target),
    lazy = capabilities(x$target)$lazy
  )
}
#' @export
capabilities.tw_lake_target <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = TRUE,
    partition = TRUE,
    immutable = TRUE
  )
}
#' @export
capabilities.tw_lake <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = !isTRUE(x$config$read_only),
    lazy = TRUE,
    transactions = TRUE,
    partition = TRUE,
    immutable = TRUE
  )
}
#' @export
capabilities.tw_sql_transform <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
