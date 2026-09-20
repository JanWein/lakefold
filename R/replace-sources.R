#' Replace inputs without rebuilding a workflow
#'
#' Edits definitions only: no readers, transformations, connections or dbt
#' commands run. Execute the returned definition with [run()] or [publish()],
#' or rebuild its [as_targets()] graph to let targets cache unaffected products.
#'
#' For products, names select a root source alias (including the qualified
#' transformation aliases shown by internal dependency inspection) or a nested
#' product ID. A product ID updates the ordinary delivery at the end of its
#' single-primary-input chain, retaining every product's transforms, checks and
#' target in every reference, including
#' lookups. Products with multiple primary inputs need an explicit edited
#' definition instead. A replacement product with the same ID explicitly
#' replaces the whole definition. If a root alias also names that same product, the product
#' ID interpretation applies. Other alias/ID collisions are rejected. Pinned
#' results are not product definitions: they change only when their root source
#' alias is explicitly selected. To change a deeper pinned input, replace its
#' containing product with an edited definition. Overlapping edits that discard
#' another requested replacement are rejected.
#'
#' For managed dbt projects, names select existing source table aliases. An alias
#' appearing in more than one group is ambiguous; use `group.table` instead.
#' Replacements must be successful immutable lake results in the same catalog.
#' Unselected bindings retain their exact release IDs. Files are updated only
#' when the project executes. External-profile projects are not supported.
#'
#' @param x A product or managed [dbt_project()] definition.
#' @param ... Named replacement sources, using the same values as [add_source()]
#'   for products. For managed dbt, successful published lake results.
#' @returns An updated definition of the same class as `x`.
#' @export
#' @examples
#' orders <- product("orders", data.frame(amount = 10))
#' totals <- product("totals", orders)
#' corrected <- totals |> replace_sources(orders = data.frame(amount = 20))
#' corrected |> run() |> collect()
replace_sources <- function(x, ...) {
  replace_sources_list(x, list(...))
}

replace_sources_list <- function(x, replacements) {
  nms <- names(replacements)
  if (
    !length(replacements) ||
      is.null(nms) ||
      anyNA(nms) ||
      any(!nzchar(nms)) ||
      anyDuplicated(nms)
  ) {
    abort("Supply uniquely named, non-empty replacement sources.")
  }
  if (inherits(x, "tw_dbt_project")) {
    return(replace_dbt_sources(x, replacements))
  }
  if (!inherits(x, "tw_product")) {
    abort("x must be a product or a managed dbt project definition.")
  }
  definitions <- replacement_graph(x)
  ids <- setdiff(names(definitions), x$id)
  sources <- product_sources(x)
  modes <- stats::setNames(rep("alias", length(nms)), nms)
  for (name in nms) {
    alias <- name %in% names(sources)
    id <- name %in% ids
    if (!alias && !id) {
      abort(paste0(
        "Unknown replacement source: ",
        name,
        ". Available names: ",
        paste(sort(unique(c(names(sources), ids))), collapse = ", "),
        "."
      ))
    }
    if (
      alias &&
        id &&
        !(inherits(sources[[name]], "tw_product") &&
          identical(sources[[name]]$id, name))
    ) {
      abort(paste("Ambiguous root alias and product ID:", name))
    }
    if (id) {
      modes[[name]] <- "id"
    }
    replacement <- replacements[[name]]
    if (id) {
      if (inherits(replacement, "tw_product")) {
        if (!identical(replacement$id, name)) {
          abort(paste(
            "A replacement product must retain the selected ID:",
            name
          ))
        }
      } else {
        replacement <- replace_primary_delivery(
          definitions[[name]],
          replacement
        )
      }
    }
    if (
      !id &&
        inherits(sources[[name]], "tw_product") &&
        !inherits(replacement, "tw_product")
    ) {
      replacement <- replace_primary_delivery(sources[[name]], replacement)
    }
    replacements[[name]] <- normalize_source(replacement, x$id, name)
  }
  applied <- character()
  visit <- function(node, root = FALSE) {
    inputs <- product_sources(node)
    for (alias in names(inputs)) {
      source <- inputs[[alias]]
      selected <- if (root && alias %in% nms && modes[[alias]] == "alias") {
        alias
      } else if (
        inherits(source, "tw_product") &&
          source$id %in% nms &&
          modes[[source$id]] == "id"
      ) {
        source$id
      } else {
        NULL
      }
      if (!is.null(selected)) {
        inputs[[alias]] <- replacements[[selected]]
        applied <<- union(applied, selected)
      } else if (inherits(source, "tw_product")) {
        inputs[[alias]] <- visit(source)
      }
    }
    replace_product_sources(node, inputs)
  }
  out <- visit(x, root = TRUE)
  unused <- setdiff(nms, applied)
  if (length(unused)) {
    abort(paste(
      "Overlapping replacements discard requested sources:",
      paste(unused, collapse = ", ")
    ))
  }
  replacement_graph(out)
  out
}

replace_primary_delivery <- function(product, replacement) {
  if (length(product$sources) != 1L) {
    abort(paste0(
      "Replacing a product input requires exactly one primary source at `",
      product$id,
      "`. Use sources = list(name = value) to select a deeper input or supply an edited product definition."
    ))
  }
  source <- product$sources[[1L]]
  if (inherits(source, "tw_product")) {
    replacement <- replace_primary_delivery(source, replacement)
  }
  add_source(product, replacement, replace = TRUE)
}

replacement_graph <- function(x) {
  definitions <- list()
  visit <- function(node, stack = character()) {
    if (node$id %in% stack) {
      abort(paste(
        "Product dependency cycle:",
        paste(c(stack, node$id), collapse = " -> ")
      ))
    }
    if (node$id %in% names(definitions)) {
      if (!identical(definitions[[node$id]], node)) {
        abort(paste("Different product definitions share the ID:", node$id))
      }
      return(invisible(NULL))
    }
    for (source in product_sources(node)) {
      if (inherits(source, "tw_product")) visit(source, c(stack, node$id))
    }
    definitions[[node$id]] <<- node
    invisible(NULL)
  }
  visit(x)
  definitions
}

replace_dbt_sources <- function(x, replacements) {
  if (is.null(x$lake)) {
    abort(
      "Source replacement requires a managed dbt project with lake configuration."
    )
  }
  slots <- list()
  for (group in names(x$source_groups)) {
    for (alias in names(x$source_groups[[group]])) {
      slots[[length(slots) + 1L]] <- c(group = group, alias = alias)
    }
  }
  selected <- integer()
  for (name in names(replacements)) {
    matches <- which(vapply(
      slots,
      function(slot) {
        name == slot[["alias"]] ||
          name == paste(slot[["group"]], slot[["alias"]], sep = ".")
      },
      logical(1)
    ))
    if (!length(matches)) {
      abort(paste0(
        "Unknown dbt source binding: ",
        name,
        ". Available names: ",
        paste(
          vapply(
            slots,
            function(slot) paste(slot, collapse = "."),
            character(1)
          ),
          collapse = ", "
        ),
        "."
      ))
    }
    if (length(matches) != 1L) {
      abort(paste("Ambiguous dbt source binding; use group.table:", name))
    }
    if (matches %in% selected) {
      abort("Two replacements select the same dbt source binding.")
    }
    selected <- c(selected, matches)
    slot <- slots[[matches]]
    refs <- dbt_source_references(stats::setNames(
      list(replacements[[name]]),
      slot[["alias"]]
    ))
    dbt_source_catalog(refs, x$lake)
    x$source_groups[[slot[["group"]]]][[slot[["alias"]]]] <- refs[[1L]]
  }
  x
}
