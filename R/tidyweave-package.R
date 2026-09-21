#' tidyweave: modular checked data products
#'
#' Compose reusable product specifications, preparation recipes and execution
#' workflows. Definitions are connection-free R values. Executions return
#' results with data references, quality outcomes and lineage.
#'
#' @section Product specifications:
#' [tw_product()] defines output identity. Add a [tw_contract()] for schema and
#' keys and [tw_quality_rule()] specifications for value requirements using
#' [tw_add_contract()] and [tw_add_quality()]. Requirements apply to prepared
#' output. See `vignette("first-product")`.
#'
#' @section Preparation recipes:
#' [tw_recipe()] stores ordered, deferred [tw_step_mutate()] and other preparation
#' steps. Reuse a recipe across products. [tw_step_transform()] accepts an
#' ordinary function or adapter; [tw_step_lookup()] adds a checked relationship.
#' [tw_set_engine()] chooses a supported quality or relationship implementation.
#' Recipes have no fitted training state. See `vignette("preparation-recipes")`
#' and `vignette("engines")`.
#'
#' @section Workflow assembly:
#' Start with [tw_workflow()], then [tw_add_product()] and [tw_add_recipe()].
#' Update, remove or extract each component independently. Add a source or bind
#' `data =` at execution. Use [tw_inspect()] and [tw_plan()] without reading data.
#' See `vignette("modular-workflows")`.
#'
#' @section Execution and results:
#' [tw_trial()] prepares and checks a delivery with framework writers disabled.
#' [tw_run()] executes configured writers; [tw_publish()] saves checked output.
#' [tw_collect()] returns usable data. [tw_status()], [tw_quality_report()] and
#' [tw_lineage()] explain the attempt. Lake results identify immutable releases;
#' other targets retain their own persistence guarantees.
#'
#' @section Learn more:
#' Begin with `vignette("get-started")`. `vignette("learn")` groups task guides,
#' integrations and case studies. `vignette("api-migration")` explains the
#' prefixed API and extension methods. All public tidyweave functions start
#' with `tw_`; ordinary dplyr methods remain available through dplyr.
#'
#' @section Extend and operate:
#' Public S3 protocols support sources, transformations, quality engines,
#' targets and catalogs. See `vignette("extending-tidyweave")`. Caller-supplied
#' connections remain caller-owned. Local lake writes need one coordinated
#' writer; PostgreSQL catalogs coordinate package writes through advisory locks.
#' Catalog delivery is outside the data transaction. Scheduling, report rendering
#' and access management remain with existing tools. Interfaces are experimental
#' until the first stable release candidate.
#'
#' @seealso [tw_product()], [tw_recipe()], [tw_workflow()]
#' @keywords internal
"_PACKAGE"
