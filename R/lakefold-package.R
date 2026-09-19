#' lakefold: R workflows for data lakes and dbt
#'
#' Define file ingestion and publication in R, delegate SQL builds to dbt,
#' and consume lazy relations through dplyr and dm.
#'
#' @section Start here:
#' * `vignette("getting-started")`: an executable, offline ingestion example.
#' * `vignette("dbt-workflows")`: dbt setup, builds, diagnostics and dm models.
#' * `vignette("workflow-design")`: specifications and the execution lifecycle.
#' * `vignette("quality-history")`: quality gates and reproducible releases.
#' * `vignette("products-metrics")`: products, metrics and report manifests.
#'
#' @section Two execution paths:
#' [dl_ingest()] and [dl_execute()] publish immutable lakefold releases after
#' contract validation. [dl_dbt_build()] runs dbt models and tests, which have
#' dbt's own materialization semantics. A successful dbt build does not create
#' a lakefold release automatically. [dl_model()] opens governed releases;
#' [dl_dbt_model()] opens current dbt relations.
#'
#' @section Resource ownership:
#' Specifications do not contain live database connections. Close connections
#' with [dl_disconnect()]. Close local catalog connections before invoking dbt
#' in another process. Lazy tables require their originating connection to
#' remain open. The lakefold registry requires a single writer.
#'
#' @seealso [dl_config()], [dl_pipeline()], [dl_dbt_project()]
#' @keywords internal
"_PACKAGE"
