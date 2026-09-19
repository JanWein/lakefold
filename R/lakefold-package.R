#' lakefold: checked, versioned data for recurring reports
#'
#' Keep incoming files, check proposed tables and publish data that reports can
#' read consistently. Corrections create new releases while earlier versions
#' remain available. Start locally with [dl_open()], [dl_write()] and [dl_read()].
#' Add business checks, reusable tables and recorded metrics when needed.
#'
#' @section Why use lakefold?:
#' A corrected monthly delivery should update the current dataset without losing
#' the inputs behind a report already issued. A failed delivery should leave the
#' previous successful release available. lakefold records these steps and lets
#' you read either the current table or an exact historical release.
#' Publishing means making checked data readable in your lake, not on the internet.
#' See `vignette("why-lakefold")` for an illustrated explanation and
#' `vignette("getting-started")` for a complete monthly reporting example.
#'
#' @section Design principles:
#' Define, inspect, execute and examine results through a small set of consistent
#' concepts. Sources, contracts, pipelines, products, metrics and releases have
#' explicit responsibilities. Integrations can be adopted as the workflow needs
#' them. See `vignette("design-review")` for composition and extension boundaries.
#'
#' @section Start here:
#' * `vignette("why-lakefold")`: purpose, benefits and concepts in plain language.
#' * `vignette("getting-started")`: deliveries, corrections, checks and reports, step by step.
#' * `vignette("dbt-workflows")`: dbt setup, builds, diagnostics and dm models.
#' * `vignette("workflow-design")`: specifications and the execution lifecycle.
#' * `vignette("quality-history")`: quality gates and reproducible releases.
#' * `vignette("quality-gates")`: pointblank, input gates and quality reports.
#' * `vignette("products-metrics")`: products, metrics and report manifests.
#'
#' @section Two execution paths:
#' [dl_ingest()] and [dl_execute()] publish immutable lakefold releases after
#' contract validation. [dl_dbt_build()] runs dbt models and tests, which have
#' dbt's own materialization semantics. A successful dbt build does not create
#' a lakefold release automatically. [dl_model()] opens governed releases;
#' [dl_dbt_model()] opens current dbt relations.
#' [dl_dbt_publish()] snapshots one current dbt relation, validates its contract
#' and publishes it as a governed release. [dl_status()] and [dl_quality()]
#' provide common inspection functions across both execution paths.
#'
#' @section Resource ownership:
#' Specifications do not contain live database connections. Close connections
#' with [dl_close()] or [dl_disconnect()]. Close local catalog connections before invoking dbt
#' in another process. Lazy tables require their originating connection to
#' remain open. The lakefold registry requires a single writer.
#'
#' @seealso [dl_config()], [dl_pipeline()], [dl_dbt_project()]
#' @keywords internal
"_PACKAGE"
