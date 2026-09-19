# lakefold 0.3.0

* The package is now called **lakefold** (formerly dataloom). Install and attach
  `lakefold`; existing `dl_*` functions, registry tables, contract export format
  and explicitly configured storage paths remain compatible.
* `dl_dbt_build()` and `dl_dbt_test()` run dbt through its CLI, preserve diagnostics
  and isolate artifacts for every invocation.
* `dl_dbt_init()` creates a local dbt-duckdb/DuckLake starter with synthetic data,
  models and data tests, without overwriting existing files.
* `dl_dbt_lineage()` exposes manifest dependency edges as a tibble.
* `dl_dbt_model()` opens materialized dbt relations as a lazy `dm` with explicit
  primary and foreign keys. These are current relations, not governed releases.
* `dl_dbt_project()` separates project specification from process execution.
* `dl_dbt_status()` reads structured results from an invocation or artifact path.
* `dl_execute()` supports dbt project specifications.
* `dl_ingest()` provides a compact entry point to governed file ingestion.

# lakefold 0.2.0

* Connection-free `dl_config()` constructor and pipeline definitions.
* `dl_plan()` and compact print methods for inspectable specifications.
* Named, ordered transformation steps between extraction and validation.
* Object-first `dl_execute()` generic for pipelines, products and metrics.
* Earlier errors for invalid pipeline order and invalid transform results.
* Empty custom metric results are rejected before reporting.
* Correct backend matrix variable for the full CI test suite.
* Complete tutorials, explicit tidymodels comparison and prioritized design review.
* Registry schema unchanged; existing execution functions remain supported.

# lakefold 0.1.0

* Initial implementation (then named dataloom) of governed file ingestion,
  contracts, quality gates, immutable releases, products, dm models, metrics,
  report manifests and a read-only catalog.
