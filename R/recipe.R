#' Define a reusable data preparation recipe
#'
#' A recipe contains ordered transformations, independently of product identity,
#' primary inputs, output contracts and destinations. Construction never reads
#' data. Attach it with [add_recipe()] to a product or [workflow()]. Recipes are
#' ordinary R values: adding a step returns a new value and leaves the original
#' unchanged. Expressions use dplyr data masking and retain their environments.
#'
#' These are data preparation instructions, not fitted preprocessing models.
#' There is no training or implicit `prep()`/`bake()` phase. Use [trial()] on
#' the assembled workflow to inspect checked output, then [publish()] to save it.
#' @returns A recipe specification.
#' @export
#' @examples
#' preparation <- recipe() |>
#'   step_mutate(amount = round(amount, 2)) |>
#'   step_filter(amount >= 0)
#' product("orders", data.frame(amount = c(10.123, 20))) |>
#'   add_recipe(preparation) |>
#'   trial() |>
#'   collect()
recipe <- function() {
  structure(list(steps = list()), class = "tw_recipe")
}

assert_recipe <- function(x) {
  if (!inherits(x, "tw_recipe")) {
    abort("Start with recipe() before adding preparation steps.")
  }
  invisible(x)
}

#' Add a deferred preparation step
#'
#' Steps execute in addition order using the existing dplyr and transformation
#' adapters. No implicit collection is performed. Use `step_transform()` for
#' an ordinary function, formula using `.x`, or an existing transform adapter.
#' It also accepts an engine-configured [lookup_spec()].
#' @param x A [recipe()] specification.
#' @param ... Arguments passed to the corresponding dplyr verb at execution.
#' @param transform Function, formula using `.x`, or transformation adapter.
#' @param name Optional unique step name for `step_transform()`.
#' @param .by,.preserve,.groups,.keep_all Arguments with their dplyr meanings.
#' @returns An updated recipe. The original is unchanged.
#' @export
#' @examples
#' recipe() |>
#'   step_mutate(net = gross / 1.19) |>
#'   step_select(id, net)
step_transform <- function(x, transform, name = NULL) {
  assert_recipe(x)
  holder <- product("recipe")
  holder$transforms <- x$steps
  holder <- add_transform(holder, transform, name)
  x$steps <- holder$transforms
  x
}

recipe_dplyr_step <- function(x, verb, args) {
  assert_recipe(x)
  step_transform(
    x,
    structure(list(verb = verb, args = args), class = "tw_dplyr_transform"),
    name = paste0(verb, "_", length(x$steps) + 1L)
  )
}

#' @rdname step_transform
#' @export
step_mutate <- function(x, ...) {
  recipe_dplyr_step(x, "mutate", rlang::enquos(...))
}

#' @rdname step_transform
#' @export
step_filter <- function(x, ..., .by = NULL, .preserve = FALSE) {
  args <- rlang::enquos(...)
  if (!missing(.by)) {
    args$.by <- rlang::enquo(.by)
  }
  if (!missing(.preserve)) {
    args$.preserve <- rlang::enquo(.preserve)
  }
  recipe_dplyr_step(x, "filter", args)
}

#' @rdname step_transform
#' @export
step_select <- function(x, ...) {
  recipe_dplyr_step(x, "select", rlang::enquos(...))
}

#' @rdname step_transform
#' @export
step_rename <- function(x, ...) {
  recipe_dplyr_step(x, "rename", rlang::enquos(...))
}

#' @rdname step_transform
#' @export
step_arrange <- function(x, ...) {
  recipe_dplyr_step(x, "arrange", rlang::enquos(...))
}

#' @rdname step_transform
#' @export
step_summarise <- function(x, ..., .by = NULL, .groups = NULL) {
  args <- rlang::enquos(...)
  if (!missing(.by)) {
    args$.by <- rlang::enquo(.by)
  }
  if (!missing(.groups)) {
    args$.groups <- rlang::enquo(.groups)
  }
  recipe_dplyr_step(x, "summarise", args)
}

#' @rdname step_transform
#' @export
step_distinct <- function(x, ..., .keep_all = FALSE) {
  args <- rlang::enquos(...)
  if (!missing(.keep_all)) {
    args$.keep_all <- rlang::enquo(.keep_all)
  }
  recipe_dplyr_step(x, "distinct", args)
}

#' Add a checked lookup to a recipe
#'
#' Uses the same dependency resolution and relationship checks as [add_lookup()].
#' Reusable lookup specifications can instead be passed to [step_transform()].
#' @inheritParams add_lookup
#' @param x A [recipe()] specification.
#' @returns An updated recipe.
#' @export
#' @examples
#' recipe() |>
#'   step_lookup(data.frame(id = 1:2, region = c("North", "South")),
#'     by = "id", name = "customers")
step_lookup <- function(
  x,
  source,
  by,
  engine = c("native", "dm"),
  unmatched = c("error", "keep"),
  suffix = c(".x", ".y"),
  name = NULL,
  table = NULL
) {
  assert_recipe(x)
  if (is.null(name)) {
    name <- if (!is.null(table)) {
      table
    } else if (inherits(source, "tw_product")) {
      source$id
    } else if (is.symbol(substitute(source))) {
      as.character(substitute(source))
    }
  }
  holder <- product("recipe")
  holder$transforms <- x$steps
  args <- list(
    x = holder,
    source = source,
    by = by,
    unmatched = match.arg(unmatched),
    suffix = suffix,
    name = name,
    table = table
  )
  if (!missing(engine)) {
    args$engine <- match.arg(engine)
  }
  x$steps <- do.call(add_lookup, args)$transforms
  x
}

#' @export
inspect.tw_recipe <- function(x, ...) {
  list(type = "recipe", steps = lapply(x$steps, inspect))
}

#' @export
print.tw_recipe <- function(x, ...) {
  cat("<recipe> ", length(x$steps), " preparation step(s)\n", sep = "")
  if (length(x$steps)) {
    print(tibble::tibble(
      step = names(x$steps),
      operation = vapply(x$steps, \(step) inspect(step)$type, character(1))
    ))
  }
  invisible(x)
}
