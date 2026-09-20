# tidyweave 0.8.0

* The package is renamed to tidyweave. The development API now uses clear,
  unprefixed verbs and does not retain compatibility aliases.
* `run()` is the public execution entry point; low-level pipeline, ingestion
  and build helpers are internal implementation details.
* One product class supports named additive sources, explicit replacement,
  dependent products, cycle validation and shared upstream execution.
* DBI tables can remain lazy through compatible transformations and checks.
  Adapter capabilities and execution plans expose materialization boundaries.
* Optional adapters add transactional DBI targets, Arrow/Parquet, versioned
  pins, and httr2 API ingestion with bounded pagination.
* Durable run evidence includes failed quality checks and retryable metadata
  delivery. OpenLineage and OpenMetadata adapters keep catalog failures separate
  from data publication.
* `as_targets()` maps product dependencies into targets; `transform_dbt()`
  stages explicit input for a dbt model. `init_project()` creates a runnable
  project with optional targets, renv and Posit Connect templates.
* Quality functions accept logical row vectors. Freshness is opt-in, factors
  retain their R objects while contracts describe labels, and exact integer64
  handling protects large identifiers. `quality_reference()` checks related
  tables and `profile_data()` returns aggregate column summaries.
* English vignettes are the canonical tutorials. The architecture review and
  modern-stack comparison distinguish implemented capabilities from external
  infrastructure responsibilities.

This is an experimental breaking release. API compatibility commitments begin
with the first stable release candidate. Existing data stores are not silently
migrated from older development package names.

# tidyweave 0.7.0

- The core works without DuckDB. Install optional `duckdb` >= 1.5.5 for lake
  storage and the SQL transform adapter. Existing database workflows remain
  supported and keep their publication and versioning semantics.
- `add_source()`, `add_transform()`, `add_contract()`, `add_quality()`,
  `set_target()` and `add_catalog()` compose products with ordinary inputs.
- `collect()` returns an ordinary tibble from native or pinned lake results.
- `contract()` accepts named prototype lists and an optional identity;
  anonymous contracts inherit their product's identity.
- `inspect()` and `explain()` describe composition without execution.
- `product("name")` creates a lightweight product with sensible defaults;
  the existing derived-product constructor remains supported.
- `publish()` publishes a composed product or data frame to a local lake,
  configured storage or a custom target.
- `quality_rule()` accepts row-wise quality formulas. Missing results fail checks.
- `run()` dispatches across composed products and existing workflow objects.
  Composed runs return schema, row counts, timestamps and execution evidence.
- `source_database()` accepts DBI tables, parameterized queries and deferred
  connection factories. `sql_transform()` provides an optional DuckDB SQL transform.
- `validate()` checks product and pipeline definitions before execution.
- Source, transform, quality, target and catalog S3 interfaces allow extensions
  without core changes. Malformed quality evidence blocks publication.
- Excel paths have an optional readxl default reader.

# tidyweave 0.6.0

## Correctness

* Fingerprint complete metric expressions instead of abbreviated labels. Existing
  metric identities require a new version; historical reports are retained.
* Check missing input values for data pronouns and explicit dynamic inputs.
  Reject ambiguous duplicate-group custom metric results.
* Preserve current delivery evidence across corrections to older partitions.
* Generate framework IDs without consuming or creating R's random seed.
* Order grouped metric results deterministically before hashing, so database
  row order does not change report identity.
* Make repeated report saves ignore only calculation timestamps and retain the
  first saved evidence and native return types. Deduplicate identical measurement
  lineage edges. Retain legacy registry aliases and require recorded delivery
  evidence when notifications are requested.

## Everyday workflows

* Add `partition_by` to `write_data()` and `tw_ingest()`.
* Accept source functions returning data frames in `write_data()`.
* Accept quoted column names and compatible integer/decimal automatic schemas;
  keep explicit integer contracts strict.
* Add database-enforced read-only connections and optional metric recording.
* Add `compare()` with key checks, complete counts, bounded row previews and
  numeric summaries, and `report_read()` for saved values and manifests.
* Make metric owner, description and unit optional. Infer flow/stock defaults
  from the presence of a time column; approval and code versions remain explicit.
* Add local quality exception inspection and `cache = FALSE` for product builds.
* Add explicit abandoned-run and staging recovery with live-writer protection.
  Registry schema 3 adds ownership for new runs without rewriting prior evidence.

## Documentation and verification

* Simplify the monthly walkthrough and add an executable everyday-workflow guide,
  migration instructions, regression tests and a reproducible benchmark script.
* Expand CI beyond the two Linux backend jobs to minimum R and Windows/macOS
  compatibility checks. Results are recorded against the actual checked commit.

# tidyweave 0.5.0

* `contract()` and `contract_from()` make descriptive metadata optional.
  Contracts default to version `1.0.0`; `max_age_hours = NULL` disables the
  freshness deadline without inventing a business requirement.
* `open_lake()` rejects nonempty folders without a saved configuration so existing
  custom layouts are never shadowed by a new local lake.
* `open_lake()` creates or reopens a local folder with DuckDB defaults and a saved
  backend choice. `close_lake()` provides the matching connection helper.
* `read_release()` returns a tibble by default, with optional lazy and historical reads.
* `run()` accepts `cache = FALSE` to recheck callbacks and `cache = "current"`
  to restrict reuse to the current release. Existing historical retry behavior
  remains the default.
* `write_data()` accepts data frames and CSV, TSV or RDS paths with automatic names,
  structural schema checks and definition versions. Contracts, custom readers,
  input gates and explicit code versions are optional. Custom callbacks are
  re-evaluated by default, and explicit contracts cannot be silently dropped,
  including after a blocked first run or a blocked contract upgrade.

# tidyweave 0.4.0

* Documentation is now maintained entirely in English, including the README,
  guides, vignettes, example schemas and job templates.
* Positioning describes an independent framework that makes complex data
  workflows accessible through simple, composable R building blocks.

* The registry now migrates quality metadata additively to schema version 2,
  preserving existing releases and rejecting unsupported future schemas.
* `check_delivery()` monitors expected business dates even without an ingest
  attempt, with retryable notification failures and incident deduplication.
* `cleanup()` previews or removes expired unpublished failed-run tables while
  retaining all releases, landing files and quality evidence.
* `contract()` accepts technical operators and column descriptions/units.
* `contract_from()`, `contract_confirm()` and `contract_diff()` support
  explicit review of inferred types and semantic contract changes.
* `dbt_publish()` copies a current dbt relation into a freshly validated,
  immutable release. Changed live relations never reuse cached build evidence.
* `expect_quality()` uses the publication policy in testthat expectations.
* `tw_ingest_data()` accepts existing R data frames and archives an RDS snapshot.
* `pointblank_checks(policy = "agent")` honors native per-step action levels and
  records segment evidence. The default rule policy remains compatible.
* `pointblank_report()` exports native reports from explicitly retained agents.
* `quality_report()` exports escaped, standalone HTML or JSON check metadata.
* `status()`, `quality()`, `releases()` and `lineage()` expose common
  diagnostics, exact release evidence, cache provenance and recursive lineage.
* `tw_step_precheck()` and ingestion's `input_contract` check before Raw writes,
  preserving the final gate on the complete publication candidate.

# tidyweave 0.3.0

* The package is now called **tidyweave** (formerly dataloom). Install and attach
  `tidyweave`; existing `tw_*` functions, registry tables, contract export format
  and explicitly configured storage paths remain compatible.
* `dbt_build()` and `dbt_test()` run dbt through its CLI, preserve diagnostics
  and isolate artifacts for every invocation.
* `dbt_init()` creates a local dbt-duckdb/DuckLake starter with synthetic data,
  models and data tests, without overwriting existing files.
* `dbt_lineage()` exposes manifest dependency edges as a tibble.
* `dbt_model()` opens materialized dbt relations as a lazy `dm` with explicit
  primary and foreign keys. These are current relations, not governed releases.
* `dbt_project()` separates project specification from process execution.
* `dbt_status()` reads structured results from an invocation or artifact path.
* `tw_execute()` supports dbt project specifications.
* `tw_ingest()` provides a compact entry point to governed file ingestion.

# tidyweave 0.2.0

* Connection-free `lake_config()` constructor and pipeline definitions.
* `plan()` and compact print methods for inspectable specifications.
* Named, ordered transformation steps between extraction and validation.
* Object-first `tw_execute()` generic for pipelines, products and metrics.
* Earlier errors for invalid pipeline order and invalid transform results.
* Empty custom metric results are rejected before reporting.
* Correct backend matrix variable for the full CI test suite.
* Complete tutorials, workflow design principles and a prioritized design review.
* Registry schema unchanged; existing execution functions remain supported.

# tidyweave 0.1.0

* Initial implementation (then named dataloom) of governed file ingestion,
  contracts, quality gates, immutable releases, products, dm models, metrics,
  report manifests and a read-only catalog.
