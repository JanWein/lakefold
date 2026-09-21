#' Add an explicit transformation before validation
#'
#' Transforms are applied in order after raw extraction and before composing
#' the candidate and validating its contract. Each receives a lazy table or the
#' prior transform's data frame. No collection is performed by this step.
#' The original file and raw table remain intact. Change the pipeline version
#' and code_version whenever transformation behavior changes.
#' @param pipeline Pipeline specification after extraction and before
#'   validation.
#' @param transform Function of one data argument, returning a lazy table or
#'   data frame.
#' @param id Unique step identifier within this pipeline.
#' @return An updated pipeline specification.
#' @examples
#' pipeline <- tw_pipeline("orders.import", tw_lake_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   tw_step_land(tw_source_file("orders.file", "orders.csv", utils::read.csv)) |>
#'   tw_step_extract() |>
#'   pipeline_step_transform(function(data) dplyr::filter(data, amount > 0), "positive")
#' tw_plan(pipeline)
#' @noRd
pipeline_step_transform <- function(pipeline, transform, id) {
  if (!inherits(pipeline, "tw_pipeline")) {
    abort("Use tw_pipeline() first.")
  }
  scalar(id, "id")
  if (!is.function(transform)) {
    abort("transform must be a function.")
  }
  if (
    !identical(
      setdiff(names(pipeline$steps), c("transform", "precheck")),
      c("land", "extract")
    )
  ) {
    abort(
      "Add transforms after extraction and before validation.",
      "tw_pipeline_invalid"
    )
  }
  previous <- pipeline$steps$transform
  if (id %in% vapply(previous, `[[`, character(1), "id")) {
    abort("Transform ids must be unique.")
  }
  pipeline$steps$transform <- c(
    previous,
    list(list(id = id, transform = transform))
  )
  pipeline
}

#' Inspect the execution plan without running a product
#'
#' Shows ordered source, transformation, validation, publication and catalog
#' steps. No source is read and no callback is called. A materialization value
#' of `NA` means the component has not declared its lazy behavior; ordinary
#' functions may support either lazy or in-memory tables.
#' @param pipeline Product specification, including an incomplete definition.
#' @returns A tibble with position, step, id, target and materializes columns.
#'   The `complete` attribute reports whether structural validation succeeds.
#' @export
#' @examples
#' tw_product("orders") |>
#'   tw_add_source(data.frame(id = 1:2)) |>
#'   tw_add_transform(function(data) dplyr::filter(data, id > 1)) |>
#'   tw_plan()
tw_plan <- function(pipeline) {
  if (inherits(pipeline, "tw_product_workflow")) {
    return(product_plan(compile_product_workflow(pipeline)))
  }
  if (inherits(pipeline, "tw_product")) {
    return(product_plan(pipeline))
  }
  if (!inherits(pipeline, "tw_pipeline")) {
    abort("Use tw_pipeline() first.")
  }
  rows <- list()
  add <- function(step, id, target) {
    rows[[length(rows) + 1L]] <<- tibble::tibble(
      position = length(rows) + 1L,
      step = step,
      id = id,
      target = target
    )
  }
  for (name in names(pipeline$steps)) {
    x <- pipeline$steps[[name]]
    switch(
      name,
      land = add(name, x$id, "immutable original"),
      extract = add(name, "reader", x$layer),
      precheck = add(
        name,
        paste(x$id, x$version, sep = "@"),
        "before raw write"
      ),
      transform = for (item in x) {
        add(name, item$id, "candidate input")
      },
      validate = add(name, paste(x$id, x$version, sep = "@"), "candidate gate"),
      publish = add(name, x$asset, paste(x$layer, x$mode, sep = ":"))
    )
  }
  out <- if (length(rows)) {
    dplyr::bind_rows(rows)
  } else {
    tibble::tibble(
      position = integer(),
      step = character(),
      id = character(),
      target = character()
    )
  }
  attr(out, "complete") <- tryCatch(
    {
      check_pipeline(pipeline)
      TRUE
    },
    error = function(e) FALSE
  )
  out
}

#' Execute a pipeline, product, metric or dbt project with a consistent
#'   object-first API
#'
#' Internal dispatch for lake pipelines, metrics and dbt projects.
#' The public entry point is [tw_run()]. A connection opened here is closed on
#' exit; an existing connection remains owned by its caller.
#' @param object Pipeline, composed or derived product, metric or dbt project
#'   specification. Composed products use [tw_run()] as the shorter equivalent.
#' @param lake Connected lake or lake_config. NULL uses a pipeline's stored
#'   config.
#' @param ... Arguments forwarded to the underlying execution function.
#' @return For pipelines and products, a tw_run_result. For metrics, a tibble
#'   with a tw_manifest attribute. Return types intentionally reflect the
#'   operation.
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- tw_lake_config(
#'   tw_registry_duckdb(file.path(root, "lake.db")),
#'   tw_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- tw_connect_lake(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- tw_source_file("orders.file", path, reader = utils::read.csv)
#' contract <- tw_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' pipeline <- tw_pipeline("orders.import", config, code_version = "v1") |>
#'   tw_step_land(source) |>
#'   tw_step_extract() |>
#'   tw_step_validate(contract) |>
#'   tw_step_publish("orders")
#' tw_execute(pipeline, lake)
#' tw_disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
#' @noRd
tw_execute <- function(object, lake = NULL, ...) UseMethod("tw_execute")
#' @export
#' @noRd
tw_execute.tw_pipeline <- function(object, lake = NULL, ...) {
  with_execution_lake(
    lake,
    function(con) tw_run(object, con, ...),
    allow_null = TRUE
  )
}
#' @export
#' @noRd
tw_execute.tw_metric <- function(object, lake = NULL, ...) {
  with_execution_lake(lake, function(con) tw_measure(con, object, ...))
}
#' @export
#' @noRd
tw_execute.default <- function(object, lake = NULL, ...) {
  abort("tw_run() supports products, metrics and dbt projects.")
}
with_execution_lake <- function(lake, fn, allow_null = FALSE) {
  if (inherits(lake, "tw_config")) {
    lake <- tw_connect_lake(lake)
    on.exit(tw_disconnect_lake(lake), add = TRUE)
  }
  if (is.null(lake) && allow_null) {
    return(fn(NULL))
  }
  assert_lake(lake)
  fn(lake)
}

#' @export
print.tw_config <- function(x, ...) {
  cat(
    "<lake_config>",
    x$backend,
    "| catalog:",
    x$catalog$type,
    "| storage:",
    x$storage$type,
    "\n"
  )
  cat("Layers:", paste(x$layers, collapse = ", "), "\nNo connection opened.\n")
  invisible(x)
}
#' @export
print.tw_pipeline <- function(x, ...) {
  cat("<tw_pipeline>", x$id, "@", x$version, "| code:", x$code_version, "\n")
  plan <- tw_plan(x)
  print(plan)
  cat(
    if (isTRUE(attr(plan, "complete"))) {
      "Ready for execution.\n"
    } else {
      "Incomplete: add the remaining mandatory steps or configure layers.\n"
    }
  )
  invisible(x)
}
#' @export
print.tw_contract <- function(x, ...) {
  cat("<contract>", x$id, "@", x$version, "\n")
  cat("Grain:", x$grain, "| Owner:", x$owner, "\n")
  cat(
    "Columns:",
    paste(names(x$columns), unlist(x$columns), sep = ":", collapse = ", "),
    "\n"
  )
  cat("Key:", paste(x$key, collapse = ", "), "| Rules:", length(x$rules), "\n")
  invisible(x)
}
#' @export
print.tw_source <- function(x, ...) {
  cat("<source_file>", x$id, "@", x$version, "| local file reader\n")
  invisible(x)
}
#' @export
print.tw_metric <- function(x, ...) {
  cat(
    "<metric>",
    x$id,
    "@",
    x$version,
    "|",
    if (x$approved) "approved" else "not approved",
    "\n"
  )
  cat(
    "Product:",
    x$product,
    "| Time:",
    x$time_behavior,
    "| Unit:",
    x$unit,
    "\n"
  )
  cat("Dimensions:", paste(x$dimensions, collapse = ", "), "\n")
  invisible(x)
}
