# lakefold 0.5.0

* `dl_contract()` and `dl_contract_from()` make descriptive metadata optional.
  Contracts default to version `1.0.0`; `max_age_hours = NULL` disables the
  freshness deadline without inventing a business requirement.
* `dl_open()` creates or reopens a local folder with DuckDB defaults and a saved
  backend choice. `dl_close()` provides the matching connection helper.
* `dl_read()` returns a tibble by default, with optional lazy and historical reads.
* `dl_run()` accepts `cache = FALSE` to recheck callbacks and `cache = "current"`
  to restrict reuse to the current release. Existing historical retry behavior
  remains the default.
* `dl_write()` accepts data frames and CSV, TSV or RDS paths with automatic names,
  structural schema checks and definition versions. Contracts, custom readers,
  input gates and explicit code versions are optional. Custom callbacks are
  re-evaluated by default, and explicit contracts cannot be silently dropped.

# lakefold 0.4.0

* Documentation is now maintained entirely in English, including the README,
  guides, vignettes, example schemas and job templates.
* Positioning describes an independent framework that makes complex data
  workflows accessible through simple, composable R building blocks.

* The registry now migrates quality metadata additively to schema version 2,
  preserving existing releases and rejecting unsupported future schemas.
* `dl_check_delivery()` monitors expected business dates even without an ingest
  attempt, with retryable notification failures and incident deduplication.
* `dl_cleanup()` previews or removes expired unpublished failed-run tables while
  retaining all releases, landing files and quality evidence.
* `dl_contract()` accepts technical operators and column descriptions/units.
* `dl_contract_from()`, `dl_contract_confirm()` and `dl_contract_diff()` support
  explicit review of inferred types and semantic contract changes.
* `dl_dbt_publish()` copies a current dbt relation into a freshly validated,
  immutable release. Changed live relations never reuse cached build evidence.
* `dl_expect_quality()` uses the publication policy in testthat expectations.
* `dl_ingest_data()` accepts existing R data frames and archives an RDS snapshot.
* `dl_pointblank(policy = "agent")` honors native per-step action levels and
  records segment evidence. The default rule policy remains compatible.
* `dl_pointblank_report()` exports native reports from explicitly retained agents.
* `dl_quality_report()` exports escaped, standalone HTML or JSON check metadata.
* `dl_status()`, `dl_quality()`, `dl_releases()` and `dl_lineage()` expose common
  diagnostics, exact release evidence, cache provenance and recursive lineage.
* `dl_step_precheck()` and ingestion's `input_contract` check before Raw writes,
  preserving the final gate on the complete publication candidate.

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
* Complete tutorials, workflow design principles and a prioritized design review.
* Registry schema unchanged; existing execution functions remain supported.

# lakefold 0.1.0

* Initial implementation (then named dataloom) of governed file ingestion,
  contracts, quality gates, immutable releases, products, dm models, metrics,
  report manifests and a read-only catalog.
