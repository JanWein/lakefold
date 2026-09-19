# Feature coverage in 0.5.0

## Component responsibilities

DuckDB/DuckLake store and process tables. dbt manages SQL dependencies,
materializations and model tests. pointblank provides optional business-rule
input gates and detailed checks. dm describes explicit relationships in R.
lakefold connects these components through reusable specifications, execution
evidence and immutable releases.

The framework is designed for simple entry points and explicit composition as
workflows become more complex. Integrations retain their own responsibilities
and can be adopted as needed.

## Simple defaults added in 0.5.0

`dl_open()`, `dl_write()` and `dl_read()` provide a minimal local workflow.
Folder layout, local backend, structural schema and definition versions are
handled automatically. CSV, TSV and RDS readers are built in. `dl_close()`
closes the connection, and `dl_open()` remembers the backend when reopening.

Contracts, keys, metadata, custom readers, input checks, pointblank, dbt, dm,
metrics and remote configuration are optional. Business requirements are never
inferred from sample values. A custom contract requires only an ID and columns.
Explicit contracts cannot be omitted on subsequent writes; custom callbacks
are re-evaluated unless the caller supplies a code version for reuse.

## Existing capabilities and additions

| Capability | Available in 0.3.0 | Added in 0.4.0 |
|---|---|---|
| pointblank integration | Basic adapter with rule-level failure ratio and severity | Native warning/blocking thresholds, per-step overrides and segment evidence |
| Ingestion | Local files, unchanged landing, Raw and candidates | Separate checks before Raw and direct R data-frame ingestion |
| Contracts | Schema, required fields, keys, R rules and owner | Reviewed type drafts, differences, operator and column metadata |
| Diagnostics | Raw registry tables and dbt-specific accessors | Shared status/quality views, release history and recursive lineage |
| Reports | Quarto/Connect templates | Quality HTML/JSON, native pointblank reports and a testthat expectation |
| dbt and releases | Separate lifecycles | Explicit snapshot publication of one freshly validated relation |
| Missing deliveries | Missing file at job start and age indicators | Expected business date and deadline monitoring without an import attempt |
| Registry | Fixed schema | Versioned, additive quality-metadata migration |
| Retention | Preserved history | Preview and safe selection of expired unpublished failed-run tables |

## Current boundaries

* Registry operations require one coordinated writer. Migration and conflict
  checks do not provide distributed writer coordination.
* `dl_dbt_publish()` publishes one relation. Atomic multi-table releases with a
  shared dm gate are not implemented.
* dbt v2/Fusion and generated remote profiles for S3/PostgreSQL are unverified.
  The tested CLI path uses dbt-core and dbt-duckdb.
* RDS landing after API/Excel preparation archives the R result. File-based
  sources are required to archive the original file unchanged.
* There is no general source-plugin protocol, incremental source change-data
  capture or automatic migration of business data schemas.
* `dl_cleanup()` retains published releases, DuckLake snapshots and object-store
  files. It does not implement a general retention policy.
* Scheduling remains external. A targets adapter and a combined R/dbt task
  graph are outside the current implementation.
* OpenMetadata, commons and data-dict are not fully integrated services.
  YAML exports are explicitly limited interfaces.

## What further extensions require

These capabilities need either verified external environments or additional
behavioral contracts, such as retention rules and transaction boundaries for
multiple products. They remain explicit extension points. An embedded scheduler,
permission system, visual ETL editor and complete column lineage from arbitrary
R code are outside the current scope.

## Documentation and references

* [Executable quality guide](https://janwein.github.io/lakefold/articles/quality-gates.html)
* [pointblank action levels](https://rstudio.github.io/pointblank/reference/action_levels.html)
* [pointblank agent reports](https://rstudio.github.io/pointblank/reference/get_agent_report.html)
* [R Packages: function documentation](https://r-pkgs.org/man.html)
* [Posit skills](https://github.com/posit-dev/skills)
