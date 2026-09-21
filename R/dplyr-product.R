#' Use dplyr verbs in a product definition
#'
#' Ordinary dplyr verbs append deferred transformations to a product. They use
#' the same data masking, tidy selection and grouping rules as dplyr on the
#' acquired table. Nothing is read until [tw_run()] or [tw_publish()].
#'
#' Expressions retain their R environments. Inspection records expressions,
#' not captured values or credentials. Changing an external binding can change
#' a later run: use an explicit `code_version` when enabling lake caching, and
#' an explicit targets cue for dynamic environment or external state. To freeze
#' a small value in an expression, inject it with `!!`.
#'
#' Use [tw_add_transform()] for other functions. Multiple primary sources must
#' first be combined by a transformation; [tw_add_lookup()] adds a checked
#' auxiliary source without changing the primary table.
#' `left_join()` on a product gives guidance rather than guessing relationship
#' rules. Use `tw_add_lookup(reference, by = ..., name = "reference")` for checked
#' enrichment, or join ordinary tables inside `tw_add_transform()` for other joins.
#' @param .data,x Product definition.
#' @param ... Arguments captured and passed to the corresponding dplyr verb.
#' @param .by,.preserve,.by_group,.add,.drop,.groups,.keep_all,.before,.after,wt,sort,name
#'   Arguments with their usual dplyr meanings, evaluated during execution.
#' @returns An updated product definition.
#' @name product-dplyr
#' @importFrom dplyr mutate filter select rename relocate arrange group_by ungroup summarise distinct count left_join
#' @examples
#' orders <- tw_product("orders", data.frame(group = c("a", "a"), amount = c(10, 20))) |>
#'   dplyr::mutate(tax = amount * 0.2) |>
#'   dplyr::summarise(total = sum(amount), .by = group)
#' orders |> tw_run() |> tw_collect()
NULL

#' @export
left_join.tw_product <- function(
  x,
  y,
  by = NULL,
  copy = FALSE,
  suffix = c(".x", ".y"),
  ...
) {
  abort(paste(
    "To enrich a product with a reference table, use tw_add_lookup(reference, by = ..., name = \"reference\").",
    "It checks unique reference keys and matching input keys.",
    "For other join relationships, use dplyr::left_join() on ordinary tables inside tw_add_transform()."
  ))
}

dplyr_product_step <- function(x, verb, args) {
  tw_add_transform(
    x,
    structure(list(verb = verb, args = args), class = "tw_dplyr_transform"),
    name = paste0(verb, "_", length(x$transforms) + 1L)
  )
}

#' @rdname product-dplyr
#' @export
mutate.tw_product <- function(.data, ...) {
  dplyr_product_step(.data, "mutate", rlang::enquos(...))
}
#' @rdname product-dplyr
#' @exportS3Method dplyr::filter
filter.tw_product <- function(.data, ..., .by = NULL, .preserve = FALSE) {
  args <- rlang::enquos(...)
  if (!missing(.by)) {
    args$.by <- rlang::enquo(.by)
  }
  if (!missing(.preserve)) {
    args$.preserve <- rlang::enquo(.preserve)
  }
  dplyr_product_step(.data, "filter", args)
}
#' @rdname product-dplyr
#' @export
select.tw_product <- function(.data, ...) {
  dplyr_product_step(.data, "select", rlang::enquos(...))
}
#' @rdname product-dplyr
#' @export
rename.tw_product <- function(.data, ...) {
  dplyr_product_step(.data, "rename", rlang::enquos(...))
}
#' @rdname product-dplyr
#' @export
relocate.tw_product <- function(.data, ..., .before = NULL, .after = NULL) {
  args <- rlang::enquos(...)
  if (!missing(.before)) {
    args$.before <- rlang::enquo(.before)
  }
  if (!missing(.after)) {
    args$.after <- rlang::enquo(.after)
  }
  dplyr_product_step(.data, "relocate", args)
}
#' @rdname product-dplyr
#' @export
arrange.tw_product <- function(.data, ..., .by_group = FALSE) {
  args <- rlang::enquos(...)
  if (!missing(.by_group)) {
    args$.by_group <- rlang::enquo(.by_group)
  }
  dplyr_product_step(.data, "arrange", args)
}
#' @rdname product-dplyr
#' @export
group_by.tw_product <- function(
  .data,
  ...,
  .add = FALSE,
  .drop = dplyr::group_by_drop_default(.data)
) {
  args <- rlang::enquos(...)
  if (!missing(.add)) {
    args$.add <- rlang::enquo(.add)
  }
  if (!missing(.drop)) {
    args$.drop <- rlang::enquo(.drop)
  }
  dplyr_product_step(.data, "group_by", args)
}
#' @rdname product-dplyr
#' @export
ungroup.tw_product <- function(x, ...) {
  dplyr_product_step(x, "ungroup", rlang::enquos(...))
}
#' @rdname product-dplyr
#' @export
summarise.tw_product <- function(.data, ..., .by = NULL, .groups = NULL) {
  args <- rlang::enquos(...)
  if (!missing(.by)) {
    args$.by <- rlang::enquo(.by)
  }
  if (!missing(.groups)) {
    args$.groups <- rlang::enquo(.groups)
  }
  dplyr_product_step(.data, "summarise", args)
}
#' @rdname product-dplyr
#' @export
distinct.tw_product <- function(.data, ..., .keep_all = FALSE) {
  args <- rlang::enquos(...)
  if (!missing(.keep_all)) {
    args$.keep_all <- rlang::enquo(.keep_all)
  }
  dplyr_product_step(.data, "distinct", args)
}
#' @rdname product-dplyr
#' @export
count.tw_product <- function(x, ..., wt = NULL, sort = FALSE, name = NULL) {
  args <- rlang::enquos(...)
  if (!missing(wt)) {
    args$wt <- rlang::enquo(wt)
  }
  if (!missing(sort)) {
    args$sort <- rlang::enquo(sort)
  }
  if (!missing(name)) {
    args$name <- rlang::enquo(name)
  }
  dplyr_product_step(x, "count", args)
}

#' @export
tw_execute_transform.tw_dplyr_transform <- function(transform, data, ...) {
  table_result(data, paste0("dplyr::", transform$verb, "() input"))
  args <- as.list(transform$args)
  ordinary <- switch(
    transform$verb,
    mutate = ".keep",
    filter = ".preserve",
    arrange = c(".by_group", ".locale"),
    group_by = c(".add", ".drop"),
    summarise = ".groups",
    distinct = ".keep_all",
    count = c("sort", "name", ".drop"),
    character()
  )
  for (name in intersect(names(args), ordinary)) {
    args[name] <- list(rlang::eval_tidy(args[[name]]))
  }
  implementation <- getExportedValue("dplyr", transform$verb)
  rlang::inject(implementation(data, !!!args))
}
#' @export
tw_check_component.tw_dplyr_transform <- function(x, ...) {
  if (
    !x$verb %in%
      c(
        "mutate",
        "filter",
        "select",
        "rename",
        "relocate",
        "arrange",
        "group_by",
        "ungroup",
        "summarise",
        "distinct",
        "count"
      )
  ) {
    abort("Unknown deferred dplyr verb.")
  }
  invisible(x)
}
#' @export
tw_inspect.tw_dplyr_transform <- function(x, ...) {
  list(type = paste0("dplyr::", x$verb), arguments = canonical(x$args))
}
#' @export
tw_capabilities.tw_dplyr_transform <- function(x, ...) {
  tw_component_capabilities(lazy = TRUE)
}
