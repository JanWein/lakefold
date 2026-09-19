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
#' @export
#' @examples
#' pipeline <- dl_pipeline("orders.import", dl_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   dl_step_land(dl_source("orders.file", "orders.csv", utils::read.csv)) |>
#'   dl_step_extract() |>
#'   dl_step_transform(function(data) dplyr::filter(data, amount > 0), "positive")
#' dl_plan(pipeline)
dl_step_transform <- function(pipeline, transform, id) {
  if (!inherits(pipeline, "dl_pipeline")) {
    abort("Use dl_pipeline() first.")
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
      "dl_pipeline_invalid"
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

#' Inspect a pipeline without executing it
#'
#' Does not connect, read source files, execute user functions or write
#'   metadata.
#' Incomplete specifications can be inspected. This is a declared plan, not a
#' dry-run of SQL, file availability, permissions or data quality.
#' @param pipeline A pipeline or composed product specification.
#' @return A tibble with position, step, id and target columns. The `complete`
#'   attribute indicates whether the mandatory steps and configured layers
#'   validate.
#' @export
#' @examples
#' dl_pipeline("orders.import", dl_config(backend = "duckdb"),
#'   code_version = "v1") |> dl_plan()
dl_plan <- function(pipeline) {
  if (inherits(pipeline, "dl_product_spec")) {
    return(product_plan(pipeline))
  }
  if (!inherits(pipeline, "dl_pipeline")) {
    abort("Use dl_pipeline() first.")
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
#' Pipelines delegate to dl_run(), products to dl_build() and metrics to
#' dl_measure(). Their original functions remain supported. Products and metrics
#' require an explicit lake or dl_config. A connection opened here is closed on
#' exit; an existing connection remains owned by its caller.
#' @param object Pipeline, composed or derived product, metric or dbt project
#'   specification. Composed products use [dl_run()] as the shorter equivalent.
#' @param lake Connected lake or dl_config. NULL uses a pipeline's stored
#'   config.
#' @param ... Arguments forwarded to the underlying execution function.
#' @return For pipelines and products, a dl_run_result. For metrics, a tibble
#'   with a dl_manifest attribute. Return types intentionally reflect the
#'   operation.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dl_source("orders.file", path, reader = utils::read.csv)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' pipeline <- dl_pipeline("orders.import", config, code_version = "v1") |>
#'   dl_step_land(source) |>
#'   dl_step_extract() |>
#'   dl_step_validate(contract) |>
#'   dl_step_publish("orders")
#' dl_execute(pipeline, lake)
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_execute <- function(object, lake = NULL, ...) UseMethod("dl_execute")
#' @export
dl_execute.dl_pipeline <- function(object, lake = NULL, ...) {
  with_execution_lake(
    lake,
    function(con) dl_run(object, con, ...),
    allow_null = TRUE
  )
}
#' @export
dl_execute.dl_product <- function(object, lake = NULL, ...) {
  with_execution_lake(lake, function(con) dl_build(con, object, ...))
}
#' @export
dl_execute.dl_metric <- function(object, lake = NULL, ...) {
  with_execution_lake(lake, function(con) dl_measure(con, object, ...))
}
#' @export
dl_execute.default <- function(object, lake = NULL, ...) {
  abort("dl_execute() supports pipelines, products, metrics and dbt projects.")
}
with_execution_lake <- function(lake, fn, allow_null = FALSE) {
  if (inherits(lake, "dl_config")) {
    lake <- dl_connect(lake)
    on.exit(dl_disconnect(lake), add = TRUE)
  }
  if (is.null(lake) && allow_null) {
    return(fn(NULL))
  }
  assert_lake(lake)
  fn(lake)
}

#' @export
print.dl_config <- function(x, ...) {
  cat(
    "<dl_config>",
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
print.dl_pipeline <- function(x, ...) {
  cat("<dl_pipeline>", x$id, "@", x$version, "| code:", x$code_version, "\n")
  plan <- dl_plan(x)
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
print.dl_contract <- function(x, ...) {
  cat("<dl_contract>", x$id, "@", x$version, "\n")
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
print.dl_source <- function(x, ...) {
  cat("<dl_source>", x$id, "@", x$version, "| local file reader\n")
  invisible(x)
}
#' @export
print.dl_product <- function(x, ...) {
  cat(
    "<dl_product>",
    x$id,
    "@",
    x$version,
    "\nInputs:",
    paste(names(x$inputs), unlist(x$inputs), sep = "=", collapse = ", "),
    "\n"
  )
  cat("Output layer:", x$layer, "| Contract:", x$contract$id, "\n")
  invisible(x)
}
#' @export
print.dl_metric <- function(x, ...) {
  cat(
    "<dl_metric>",
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
