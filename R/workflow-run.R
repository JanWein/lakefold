#' Define a modular product workflow or a delivery dependency graph
#'
#' Call `tw_workflow()` without step functions to start a modular assembly with
#' [tw_add_product()], [tw_add_recipe()] and [tw_add_source()]. Bind data at definition
#' time or with `tw_trial(flow, data = delivery)`. Use [tw_execution_config()] for
#' optional engine defaults. Each component can be extracted or replaced.
#'
#' Named functions describe the receipt, preparation and dbt steps once.
#' Each function argument names an input or another step. Steps execute in
#' dependency order; a failed step blocks its consumers. Results remain ordinary
#' R values, so existing [tw_ingest()], [tw_publish()] and dbt calls keep their meaning.
#' Keep report issuance outside the workflow as an explicit final decision.
#'
#' On correction, pass replacement `inputs` and the `previous` workflow result
#' to [tw_run()]. Unchanged successful branches are reused; changed inputs and their
#' consumers rerun. Failed branches retry on the next explicit call. Change
#' `code_version` whenever code, captured values or dependencies change. Use
#' `refresh` for named steps whose external sources changed without a new input.
#' This is sequential orchestration, not a scheduler or a distributed transaction.
#' Already committed steps stay committed if a later step fails.
#' @param ... Named step functions. Their arguments must name dependencies;
#'   defaults and `...` in step functions are not supported.
#' @param inputs Named list of initial input values.
#' @param code_version Explicit version of workflow code and dependencies.
#'   Required for function dependency graphs; optional for modular workflows.
#' @param execution Optional connection-free [tw_execution_config()] for a modular
#'   workflow. Function graphs configure execution inside their steps.
#' @returns A workflow specification. Modular workflows return ordinary product
#'   run results from [tw_trial()], [tw_run()] or [tw_publish()]. Function dependency
#'   graphs return named `results`, effective `inputs`, and a step `status` table.
#' @export
#' @examples
#' spec <- tw_product("orders") |> tw_add_quality(~ amount >= 0)
#' preparation <- tw_recipe() |> tw_step_mutate(amount = round(amount, 2))
#' flow <- tw_workflow() |> tw_add_product(spec) |> tw_add_recipe(preparation)
#' result <- tw_trial(flow, data = data.frame(amount = c(10.123, 20)))
#' tw_collect(result)
#' tw_extract_recipe(flow)
tw_workflow <- function(
  ...,
  inputs = list(),
  code_version = NULL,
  execution = NULL
) {
  steps <- list(...)
  if (!length(steps) && identical(inputs, list())) {
    return(new_product_workflow(code_version, execution))
  }
  if (!is.null(execution)) {
    abort("Configure execution inside the function workflow's steps.")
  }
  scalar(code_version, "code_version")
  check_names <- function(x) {
    is.list(x) &&
      (!length(x) ||
        (!is.null(names(x)) &&
          !anyNA(names(x)) &&
          all(nzchar(names(x))) &&
          !anyDuplicated(names(x))))
  }
  if (
    !length(steps) ||
      !check_names(steps) ||
      !check_names(inputs) ||
      length(intersect(names(steps), names(inputs))) ||
      !all(vapply(steps, is.function, logical(1)))
  ) {
    abort(
      "Supply uniquely named step functions and inputs with distinct names."
    )
  }
  dependencies <- lapply(steps, function(step) {
    args <- formals(step)
    if (is.null(args) && is.primitive(step)) {
      abort("Wrap primitive functions in an ordinary function.")
    }
    if (
      "..." %in%
        names(args) ||
        any(vapply(
          as.list(args),
          function(x) {
            !rlang::is_missing(x)
          },
          logical(1)
        ))
    ) {
      abort(
        "Step arguments must be required named dependencies, without defaults or dots."
      )
    }
    names(args) %||% character()
  })
  if (!all(unlist(dependencies) %in% c(names(inputs), names(steps)))) {
    abort("Every step argument must name a workflow input or step.")
  }
  order <- character()
  remaining <- names(steps)
  while (length(remaining)) {
    ready <- remaining[vapply(
      dependencies[remaining],
      function(deps) {
        all(deps %in% c(names(inputs), order))
      },
      logical(1)
    )]
    if (!length(ready)) {
      abort("Workflow dependencies contain a cycle.")
    }
    order <- c(order, ready)
    remaining <- setdiff(remaining, ready)
  }
  structure(
    list(
      steps = steps,
      inputs = inputs,
      dependencies = dependencies,
      order = order,
      code_version = code_version
    ),
    class = "tw_workflow"
  )
}

#' @rdname tw_workflow
#' @param pipeline A workflow specification.
#' @param lake Unused; supply storage inside the relevant step definition.
#' @param previous Previous result from the same workflow input names.
#' @param refresh Step names to rerun even when their inputs are unchanged.
#' @param stop_on_failure Signal an error after collecting step status. Set
#'   `FALSE` to inspect failures directly; errors also retain `condition$result`.
#' @export
tw_run.tw_workflow <- function(
  pipeline,
  lake = NULL,
  inputs = list(),
  previous = NULL,
  refresh = character(),
  stop_on_failure = TRUE,
  ...
) {
  rlang::check_dots_empty()
  pipeline <- do.call(
    tw_workflow,
    c(
      pipeline$steps,
      list(inputs = pipeline$inputs, code_version = pipeline$code_version)
    )
  )
  flag(stop_on_failure, "stop_on_failure")
  if (!is.null(lake)) {
    abort("Configure storage in the workflow's step definitions.")
  }
  if (
    !is.list(inputs) ||
      (length(inputs) &&
        (is.null(names(inputs)) ||
          anyNA(names(inputs)) ||
          anyDuplicated(names(inputs)) ||
          !all(names(inputs) %in% names(pipeline$inputs))))
  ) {
    abort("Replacement inputs must name existing workflow inputs uniquely.")
  }
  if (
    !is.character(refresh) ||
      anyNA(refresh) ||
      !all(refresh %in% names(pipeline$steps))
  ) {
    abort("refresh must name existing workflow steps.")
  }
  if (
    !is.null(previous) &&
      (!inherits(previous, "tw_workflow_result") ||
        !identical(names(previous$inputs), names(pipeline$inputs)))
  ) {
    abort("previous must be a workflow result with the same input names.")
  }
  effective <- if (is.null(previous)) pipeline$inputs else previous$inputs
  if (!is.null(previous)) {
    revised <- names(pipeline$inputs)[
      !vapply(
        names(pipeline$inputs),
        function(name) {
          identical(pipeline$inputs[[name]], previous$definition$inputs[[name]])
        },
        logical(1)
      )
    ]
    effective[revised] <- pipeline$inputs[revised]
  }
  effective[names(inputs)] <- inputs
  same_code <- !is.null(previous) && identical(previous$definition, pipeline)
  changed <- if (same_code) {
    names(effective)[
      !vapply(
        names(effective),
        function(name) {
          identical(effective[[name]], previous$inputs[[name]])
        },
        logical(1)
      )
    ]
  } else {
    c(names(effective), names(pipeline$steps))
  }
  changed <- union(changed, refresh)
  results <- list()
  states <- list()
  errors <- list()
  failed <- character()
  for (name in pipeline$order) {
    deps <- pipeline$dependencies[[name]]
    if (any(deps %in% failed)) {
      state <- "skipped"
      failed <- c(failed, name)
    } else if (
      same_code &&
        !name %in% changed &&
        !any(deps %in% changed) &&
        previous$status$status[match(name, previous$status$step)] %in%
          c("completed", "reused")
    ) {
      results[name] <- previous$results[name]
      state <- "reused"
    } else {
      changed <- union(changed, name)
      value <- tryCatch(
        {
          value <- do.call(pipeline$steps[[name]], c(effective, results)[deps])
          if (
            (inherits(value, "tw_run_result") &&
              !value$status %in% c("completed", "published", "cached")) ||
              (inherits(value, "tw_dbt_result") && !isTRUE(value$success))
          ) {
            abort("Step did not complete successfully.", result = value)
          }
          list(value = value)
        },
        error = function(e) {
          errors[[name]] <<- e
          NULL
        }
      )
      if (is.null(value)) {
        state <- "failed"
        failed <- c(failed, name)
      } else {
        results[name] <- value
        state <- "completed"
      }
    }
    states[[name]] <- tibble::tibble(
      step = name,
      status = state,
      success = state %in% c("completed", "reused")
    )
  }
  out <- structure(
    list(
      results = results,
      inputs = effective,
      status = dplyr::bind_rows(states),
      errors = errors,
      definition = pipeline
    ),
    class = "tw_workflow_result"
  )
  if (length(failed) && stop_on_failure) {
    abort(
      "Workflow incomplete. Inspect tw_status(condition$result) and condition$result$errors; successful steps remain available for an explicit retry.",
      "tw_workflow_failed",
      result = out
    )
  }
  out
}

#' @export
print.tw_workflow <- function(x, ...) {
  cat("<workflow> ", x$code_version, "\n", sep = "")
  print(tibble::tibble(
    step = x$order,
    inputs = vapply(
      x$dependencies[x$order],
      function(deps) paste(deps, collapse = ", "),
      character(1)
    )
  ))
  invisible(x)
}

#' @export
print.tw_workflow_result <- function(x, ...) {
  cat("<workflow result>\n")
  print(x$status)
  cat("Step outputs: $results; retained local conditions: $errors.\n")
  invisible(x)
}
