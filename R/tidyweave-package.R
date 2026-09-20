#' tidyweave: reusable data products with optional infrastructure
#'
#' Name the table you want, add its inputs and run it. Preparation uses ordinary
#' R functions; contracts, quality rules and destinations are optional additions.
#' A product is a definition. A run result describes one execution. [collect()]
#' returns an ordinary table for further analysis.
#'
#' @section Start here:
#' [product()], [add_source()], [run()] and [collect()] form a complete in-memory
#' workflow. Add [add_transform()], [add_contract()] or [add_quality()] when
#' needed. Use [set_target()] to select storage, or [publish()] to supply a local
#' lake target. Publishing writes checked data to its destination; it does not
#' make data public on the internet.
#'
#' @section Learn by building:
#' * `vignette("why-tidyweave")`: the problem and benefits in plain language.
#' * `vignette("composing-products")`: a small workflow that grows one step at a time.
#' * `vignette("getting-started")`: corrections and reproducible monthly reports.
#' * `vignette("workflow-design")`: intent, execution, adapters and ownership.
#' * `vignette("extending-tidyweave")`: a runnable S3 extension.
#'
#' @section Optional capabilities:
#' DBI and Arrow sources support lazy work where their backends permit it.
#' pointblank and dbt keep their specialist execution semantics. Targets choose
#' persistence: a lake keeps immutable releases; a database table, Parquet file
#' or pin has its adapter's documented guarantees. [run_history()] reads optional
#' durable execution evidence. Catalog adapters deliver descriptive metadata
#' separately from data publication. [as_targets()] and [init_project()] connect
#' definitions to established project and orchestration tools.
#'
#' @section Why this architecture:
#' Readable verbs and familiar R objects keep the user interface small. Internal
#' normalization, specifications, preflight and S3 adapters make implementations
#' interchangeable. The structure draws on tidymodels without exposing modeling
#' APIs. There is no required platform object or catalog service.
#'
#' @section Boundaries:
#' Caller-supplied connections stay caller-owned; keep them open for lazy results.
#' Factory-backed DBI sources materialize before closing their owned connections.
#' Lake and local evidence writes need one coordinated writer. External catalog
#' delivery is not part of a data transaction. No scheduler, streaming engine,
#' distributed transaction system or enterprise authentication system is provided.
#' Public interfaces remain experimental until the first stable release candidate.
#'
#' @seealso [inspect()], [capabilities()], [source_database()], [target_lake()]
#' @keywords internal
"_PACKAGE"
