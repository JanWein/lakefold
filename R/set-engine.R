#' Choose an implementation without changing a specification
#'
#' Mirrors parsnip's separation of intent and implementation. Formula quality
#' rules support `"native"` and `"pointblank"`; checked lookup specifications
#' support `"native"` and `"dm"`. Engine selection never reads data or loads an
#' optional engine. Missing dependencies are reported at execution preflight.
#' These engines implement individual operations, not the whole data platform.
#' Storage is configured separately with [tw_set_target()] or `tw_publish(to = )`.
#' @param x A [tw_quality_rule()] or [tw_lookup_spec()] specification.
#' @param engine Supported engine name.
#' @param ... Reserved for extension methods. Built-in methods reject extras.
#' @returns An updated specification. The original is unchanged.
#' @export
#' @examples
#' positive <- tw_quality_rule("positive", ~ amount > 0)
#' positive |> tw_set_engine("pointblank")
tw_set_engine <- function(x, engine, ...) UseMethod("tw_set_engine")

#' @export
tw_set_engine.default <- function(x, engine, ...) {
  abort("Use tw_set_engine() with a tw_quality_rule() or tw_lookup_spec().")
}

#' @export
tw_set_engine.tw_rule <- function(x, engine, ...) {
  rlang::check_dots_empty()
  if (!identical(class(x), "tw_rule")) {
    abort("This quality extension needs its own tw_set_engine() method.")
  }
  args <- x[c("name", "check", "severity", "max_failure", "description")]
  args$engine <- engine
  do.call(tw_quality_rule, args)
}

#' @export
tw_set_engine.tw_lookup_transform <- function(x, engine, ...) {
  rlang::check_dots_empty()
  scalar(engine, "engine")
  x$engine <- match.arg(engine, c("native", "dm"))
  x$engine_explicit <- TRUE
  x
}

#' Specify a reusable checked relationship
#'
#' Defines an enrichment independently of a product or recipe. Use [tw_set_engine()]
#' to choose native or dm constraint checks, then attach it with
#' [tw_step_transform()] or [tw_add_transform()].
#' @inheritParams tw_add_lookup
#' @returns A deferred lookup transformation specification.
#' @export
#' @examples
#' customers <- data.frame(id = 1:2, region = c("North", "South"))
#' lookup <- tw_lookup_spec(customers, by = "id", name = "customers") |>
#'   tw_set_engine("native")
#' tw_recipe() |> tw_step_transform(lookup)
tw_lookup_spec <- function(
  source,
  by,
  unmatched = c("error", "keep"),
  suffix = c(".x", ".y"),
  name = NULL,
  table = NULL
) {
  if (is.null(name)) {
    name <- if (!is.null(table)) {
      table
    } else if (inherits(source, "tw_product")) {
      source$id
    } else if (is.symbol(substitute(source))) {
      as.character(substitute(source))
    }
  }
  holder <- tw_add_lookup(
    tw_product("lookup"),
    source,
    by,
    unmatched = match.arg(unmatched),
    suffix = suffix,
    name = name,
    table = table
  )
  holder$transforms[[1L]]
}

#' @export
print.tw_rule <- function(x, ...) {
  cat("<quality rule> ", x$name, "\n", sep = "")
  cat("Engine:", if (identical(x$engine, "r")) "native" else x$engine, "\n")
  cat(
    "Severity:",
    x$severity,
    "| Allowed failure proportion:",
    x$max_failure,
    "\n"
  )
  invisible(x)
}

#' @export
print.tw_lookup_transform <- function(x, ...) {
  cat("<lookup specification> ", x$name, "\n", sep = "")
  cat("Engine:", x$engine, "| Unmatched:", x$unmatched, "\n")
  cat("Keys:", paste(names(x$by), x$by, sep = " = ", collapse = ", "), "\n")
  invisible(x)
}
