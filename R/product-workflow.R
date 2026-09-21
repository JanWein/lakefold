#' Assemble product specifications and reusable recipes
#'
#' An empty [workflow()] combines one product specification, one optional
#' recipe, primary sources and an optional destination. Components remain
#' independent R values. `add_*()` rejects occupied slots; `update_*()` replaces
#' an existing slot and `remove_*()` clears it. Extraction returns the definition,
#' never executed data. These edits never read sources or invoke writers.
#'
#' A product specification may carry its own sources, checks and destination.
#' Workflow sources and destinations must not conflict with those settings.
#' Keep preparation in the recipe when using this interface: products with
#' embedded transformations are rejected by `add_product()`. Existing direct
#' product pipelines remain executable. Model products can be added directly;
#' prepare their member tables with recipes before assembling the dm model.
#'
#' [trial()], [run()] and [publish()] compile the components into the existing
#' product execution graph, retaining its quality gates, dependency sharing,
#' lazy behavior and immutable release semantics. Use `data =` at execution to
#' bind a first primary input or replace the existing single primary delivery.
#' @param x A modular [workflow()]. `add_recipe()` also accepts a table product.
#' @param product A product specification carrying identity and output checks.
#' @param recipe A preparation specification from [recipe()].
#' @returns An updated definition, or the extracted component.
#' @name workflow-components
#' @export
#' @examples
#' spec <- product("orders") |>
#'   add_contract(c(id = "integer", amount = "numeric")) |>
#'   add_quality(~ amount >= 0)
#' preparation <- recipe() |> step_mutate(amount = round(amount, 2))
#' flow <- workflow() |> add_product(spec) |> add_recipe(preparation)
#' trial(flow, data = data.frame(id = 1:2, amount = c(10.123, 20))) |>
#'   collect()
add_product <- function(x, product) {
  assert_product_workflow(x)
  if (!is.null(x$product)) {
    abort("This workflow already has a product. Use update_product().")
  }
  check_workflow_product(product)
  x$product <- product
  check_workflow_slots(x)
  x
}

new_product_workflow <- function(code_version = NULL, execution = NULL) {
  if (!is.null(code_version)) {
    scalar(code_version, "code_version")
  }
  structure(
    list(
      product = NULL,
      recipe = NULL,
      sources = list(),
      target = NULL,
      code_version = code_version,
      execution = validate_stored_execution(execution)
    ),
    class = "tw_product_workflow"
  )
}

assert_product_workflow <- function(x) {
  if (!inherits(x, "tw_product_workflow")) {
    abort("Start with an empty workflow() to compose product and recipe slots.")
  }
  invisible(x)
}

check_workflow_product <- function(x) {
  if (!inherits(x, "tw_product")) {
    abort("Supply a product() specification.")
  }
  if (length(x$transforms)) {
    abort("Keep preparation in a recipe when using add_product().")
  }
  invisible(x)
}

check_workflow_slots <- function(x) {
  if (length(x$sources) && length(x$product$sources)) {
    abort(
      "Sources are already set on the product. Supply sources in one place."
    )
  }
  if (!is.null(x$target) && !is.null(product_display_target(x$product))) {
    abort("A destination is already set on the product. Set it in one place.")
  }
  if (inherits(x$product, "tw_model_product") && length(x$recipe$steps)) {
    abort("Apply recipes to the model's member table products first.")
  }
  invisible(x)
}

#' @rdname workflow-components
#' @export
add_recipe <- function(x, recipe) {
  assert_recipe(recipe)
  if (inherits(x, "tw_product_workflow")) {
    if (!is.null(x$recipe)) {
      abort("This workflow already has a recipe. Use update_recipe().")
    }
    x$recipe <- recipe
    check_workflow_slots(x)
    return(x)
  }
  append_recipe(editable_product(x), recipe)
}

append_recipe <- function(x, recipe) {
  for (name in names(recipe$steps)) {
    x <- add_transform(x, recipe$steps[[name]], name = name)
  }
  x
}

#' @rdname workflow-components
#' @export
update_product <- function(x, product) {
  extract_product(x)
  x$product <- NULL
  add_product(x, product)
}

#' @rdname workflow-components
#' @export
update_recipe <- function(x, recipe) {
  extract_recipe(x)
  x$recipe <- NULL
  add_recipe(x, recipe)
}

#' @rdname workflow-components
#' @export
remove_product <- function(x) {
  assert_product_workflow(x)
  x$product <- NULL
  x
}

#' @rdname workflow-components
#' @export
remove_recipe <- function(x) {
  assert_product_workflow(x)
  x$recipe <- NULL
  x
}

#' @rdname workflow-components
#' @export
extract_product <- function(x) {
  assert_product_workflow(x)
  if (is.null(x$product)) {
    abort("This workflow has no product. Use add_product().")
  }
  x$product
}

#' @rdname workflow-components
#' @export
extract_recipe <- function(x) {
  assert_product_workflow(x)
  if (is.null(x$recipe)) {
    abort("This workflow has no recipe. Use add_recipe().")
  }
  x$recipe
}

compile_product_workflow <- function(x, data = NULL, sources = NULL) {
  check_workflow_slots(x)
  out <- extract_product(x)
  check_workflow_product(out)
  if (length(x$sources)) {
    out$sources <- x$sources
  }
  if (!is.null(x$recipe)) {
    out <- append_recipe(out, x$recipe)
  }
  if (!is.null(x$target)) {
    out <- set_target(out, x$target)
  }
  if (!is.null(x$execution)) {
    attr(out, "tw_execution_config") <- x$execution
  }
  if (!is.null(x$code_version)) {
    out$code_version <- x$code_version
  }
  if (!is.null(data) && !length(out$sources)) {
    out <- add_source(out, data, name = out$id)
    data <- NULL
  }
  delivery_aliases(out)
  replace_execution_sources(out, data, sources)
}

#' @export
run.tw_product_workflow <- function(
  pipeline,
  lake = NULL,
  ...,
  data = NULL,
  sources = NULL
) {
  run(compile_product_workflow(pipeline, data, sources), lake = lake, ...)
}

#' @export
publish.tw_product_workflow <- function(
  x,
  name = NULL,
  to = NULL,
  ...,
  data = NULL,
  sources = NULL
) {
  publish(compile_product_workflow(x, data, sources), name = name, to = to, ...)
}

#' @export
validate.tw_product_workflow <- function(data, contract = NULL, ...) {
  validate(compile_product_workflow(data), contract = contract, ...)
  data
}

#' @export
inspect.tw_product_workflow <- function(x, ...) {
  list(
    type = "product workflow",
    product = if (!is.null(x$product)) inspect(x$product),
    recipe = if (!is.null(x$recipe)) inspect(x$recipe),
    sources = lapply(x$sources, inspect),
    target = inspect(x$target),
    code_version = x$code_version,
    execution = workflow_execution_descriptor(x)
  )
}

#' @export
print.tw_product_workflow <- function(x, ...) {
  cat("<product workflow>\n")
  cat("Product:", x$product$id %||% "not set", "\n")
  cat("Recipe:", length(x$recipe$steps), "step(s)\n")
  cat("Sources:", length(x$sources) + length(x$product$sources), "\n")
  cat(
    "Destination:",
    inspect(
      x$target %||% product_display_target(x$product) %||% x$execution$to
    )$type,
    "\n"
  )
  invisible(x)
}

workflow_execution_descriptor <- function(x) {
  config <- x$execution %||%
    attr(x$product, "tw_execution_config", exact = TRUE)
  if (is.null(config)) {
    return(NULL)
  }
  list(
    quality = config$quality,
    relationships = config$relationships,
    target = inspect(config$to),
    layer = config$layer
  )
}
