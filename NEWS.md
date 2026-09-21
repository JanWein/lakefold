# tidyweave 0.12.0.9000

* Documentation now starts with five ordered, self-contained lessons. Task guides,
  reference and troubleshooting are separated, with consistent trial, publication
  and report examples. The complete website and its internal links are checked
  on pull requests before the main-branch Pages deployment.

* Local lake folders now preserve their ordered layers and named layer roles
  together with the backend. Reopening no longer adds default layers or rejects
  publication into an originally configured layer. Conflicting settings fail
  before connecting. Older custom folders require their original layers once;
  read-only opens never rewrite the configuration.
  New and upgraded folders use configuration format 2; older tidyweave versions
  reject this format instead of silently forgetting the layer settings.
* `open_lake()` accepts `layers` and `install_extensions`, keeping creation and
  reopening on the same entry point. A DuckLake setup tutorial walks through
  initial publication, reopening and another delivery.
* `setup_lake(path = )` accepts the same self-contained local folders as
  `open_lake()` and `lake_config(path = )`.

* `compare(first, second)` compares exact publication results and manages its
  own read-only connection.
* `measure()` accepts successful in-memory trials using the same metric
  definitions. Trial measurements retain quality evidence but cannot be issued
  as reports, even if the metric is approved.
* `quality_rows()` explicitly retrieves bounded row diagnostics for predicates,
  missing required values, duplicate keys and unmatched lookups. Row data stays
  outside persisted metadata and portable quality reports.
* `report_release()` preserves full double precision and detects small numeric
  changes after measurement. Nested columns are rejected before writing, with
  instructions to return named atomic columns. Old reports remain readable;
  legacy measurements must be recalculated before issuing new reports.
* `trial()` disables configured targets, catalogs and durable run evidence
  throughout a product graph without changing its stored definition.
* `workflow()` declares dependent receipt, preparation, dbt and measurement
  steps with ordinary named functions. Corrections rerun affected branches;
  failures block consumers while retaining successful steps for explicit retry.

# tidyweave 0.12.0

* Products built from published results reuse a retained open lake connection
  and can reopen the pinned release after that connection closes. This avoids
  opening the same DuckDB file twice on Windows.
* `filter()` re-exports the dplyr generic, so method discovery also resolves the
  correct generic in R 4.2 checks.
* Product definitions retain explicit execution defaults. Stable primary source
  names and execution-time `data` or named `sources` replacements reuse the
  existing transformations, checks and dependencies for another delivery.
* Managed dbt execution accepts named replacement bindings without reconstructing
  the project; its SQL build and final publication remain explicit steps.
* Failed-result diagnostics explain blocked work through result-level evidence.
  `quality_report()` returns a diagnostic table when no output path is supplied.
* `metric_set()` shares product, dimensions, time settings and version metadata
  across named calculations. Exploratory calculations can omit approval and code
  version; issued reports still require approved, versioned definitions.
* Measurement diagnostics resolve their exact retained source releases.
  `report_release()` accepts results first and can infer a common source lake.
* Selecting an execution quality engine no longer changes the declared contract
  fingerprint. Execution evidence still records the effective checking engine.
* The README and everyday guide recommend one task path. The insurance example
  reuses named inputs and shared metric definitions for corrections.

This is a development version. Validation results are recorded separately after
execution; these release notes do not claim production or infrastructure coverage.

# tidyweave 0.11.0

* `contract_update()` derives a new explicit contract identity while reusing
  columns and expectations. Removing or changing columns and grain requires
  explicit decisions about affected keys, non-null fields and rules.
* `execution_config()` supplies explicit quality, relationship, destination and
  layer defaults to `run()`, `publish()` and `ingest()`. Engine defaults propagate
  through dependencies; local choices win and configured targets are preserved.
* `measure()` accepts a named list of metrics and computes each selected period
  or an explicit period aggregate. `collect()` returns tidy values while the
  original measurement set retains individual release manifests.
* `replace_sources()` replaces named inputs or nested product definitions without
  rebuilding the dependency graph. Managed dbt projects accept updated logical
  source bindings through the same verb; pinned results remain explicit.
* `report_release()` and `report_read()` accept lake configurations or existing
  local folders, managing owned connections automatically. Saved batch reports
  retain measurement labels and periods and read back as tidy values.
* `status()` exposes common `outcome` categories while retaining native statuses.
  `lineage()` accepts execution results and reports recorded input evidence.

This is a development version. Stored releases and issued-report evidence retain
their integrity requirements; API stability begins at the first release candidate.

# tidyweave 0.10.0

* Products accept their primary data directly. Supported ordinary dplyr verbs
  capture deferred operations on the existing product class, with real dplyr
  evaluation at execution. Successful results are reusable sources; lake results
  pin immutable releases, while other results retain their submitted table or query.
* `add_lookup()` provides checked many-to-one enrichment with native or optional
  dm validation. Simple logical quality predicates use the native engine or
  optional Pointblank without changing their expression syntax.
* `ingest()` is data-first, including one-source products with input checks.
  `data |> ingest()` uses the local `tidyweave` folder; `to = "my-lake"` selects
  another path without a configuration object. `lake_config(path = ...)` adds
  explicit backend and layer choices without repetitive local path arguments.
* `collect()`, `explain()` and `tbl()` reuse the actual dplyr generics, so package
  attachment order no longer selects competing generics for those operations.
* Managed `dbt_project()` specifications derive connection profiles and accepted
  source bindings at execution. `run()` and `publish()` share the product grammar;
  model SQL, dbt tests and final publication gates keep their own responsibilities.
* `measure()` accepts an approved lake result and automatically pins its exact release.
* The relational insurance tutorial uses direct product calls and real dbt SQL,
  preserving grain, time, correction and issued-report examples. Its executable
  script is extracted from the canonical vignette.

This remains a development version. Breaking API changes have no compatibility
aliases before the first stable release candidate. Stored releases and report
integrity remain protected.

# tidyweave 0.9.0

* `catalog_openmetadata_dbt()` uses OpenMetadata's optional Python ingestion
  engine for invocation artifacts. `dbt_build(catalog = ...)` records delivery
  separately from the build outcome; `publish_metadata()` retries it without
  rebuilding data. Existing remote services and compatible engines are required.
* `dbt_contract()` exports explicit schema expectations and supported data tests
  as dbt model properties. Untranslated rules are reported rather than silently
  discarded; R business checks remain in R.
* `dbt_init()` can start from accepted R-ingested data and creates staging, core
  and marts models. Configure the four layers explicitly for a new lake.
* `dbt_publish()` accepts a lake configuration and an unambiguous model name.
  Contracts, asset names and definition versions have optional defaults;
  inferred contracts check structure without inventing business policy.
* `dbt_sources()` binds stable logical dbt source names to exact accepted RAW
  releases. Updating a delivery updates its generated source binding without
  rewriting SQL models or guessing physical table names.
* `ingest()` accepts ordinary R inputs with optional native or pointblank
  checks before RAW persistence. Rejected deliveries retain landing evidence
  and leave previous accepted releases available.
* `source_release()` accepts a lake configuration and reads the pinned release
  through an owned read-only connection, retaining input lineage. Connected-lake
  sources still support lazy reads.
* The English layered-data-stack guide explains receipt, preparation and
  publication step by step, with an executable example and consumer patterns
  for Shiny, Quarto and database/Parquet exports.

This is a development release. The layer layout is explicit; existing lakes
are not silently migrated. Compatibility commitments begin at the first stable
release candidate.

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
* Pin publication metadata resolves same-timestamp version ordering and verifies
  the returned reference. Ambiguous external writes require an explicit version.
* Output paths remain stable before and after directory creation, including
  Windows path normalization, so unchanged targets workflows remain cached.
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
