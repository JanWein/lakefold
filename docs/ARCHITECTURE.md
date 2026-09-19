# Architecture as of 0.5.0

lakefold organizes data workflows around definitions, execution and inspection.
Users can start with `dl_open()`, `dl_write()` and `dl_read()`, then compose steps
when their workflow needs them. Ordinary R functions and standard data objects
connect the modules.

## Execution paths

R pipelines and products preserve original inputs, validate candidates and
publish immutable releases. dbt projects build SQL models and run tests using
dbt's own semantics. Both begin with specifications and support `dl_execute()`.

`dl_dbt_status()` and `dl_dbt_lineage()` read dbt artifacts. `dl_dbt_model()` opens
current relations as dm tables. Users declare primary and foreign keys because
a SQL dependency graph cannot establish relational constraints.
`dl_dbt_publish()` copies a currently visible relation into a new candidate and
publishes it after contract validation. An earlier build's invocation ID alone
does not establish the current contents of a relation.

## Minimal local path

`dl_open()` remembers the backend and folder layout. `dl_write()` derives asset
names, structural schemas and technical versions before using the same ingestion
and final publication gate. `dl_read()` collects by default or returns a lazy
table on request. The first successfully published automatic schema is reused;
failed first deliveries do not establish a permanent baseline.

Custom contracts remain explicit on later writes. Custom readers and rules
are re-evaluated unless the caller supplies a code version for reuse. The write
facade only reuses the current release; the job runner retains historical retry
semantics. Neither path changes old published tables.

## Definitions, execution and inspection

Definitions are small classed lists: `dl_contract`, `dl_source`, `dl_pipeline`,
`dl_product` and `dl_metric`. Callbacks are ordinary R functions. Tables remain
tibbles or dbplyr lazy tables, and relational models remain dm objects.

A pipeline stores connection configuration and resolves it at execution time.
The registry lives in the separate `lake._dl` schema; lakefold does not modify
DuckLake's internal metadata tables.

| Module | Responsibility |
|---|---|
| `simple.R` | Local defaults, structural schema baselines and open/write/read entry points |
| `workflow.R` | Object-first execution, plans, transformations and compact print methods |
| `setup.R` | Local/S3 storage and DuckDB/PostgreSQL catalog configuration |
| `sources.R` | Unchanged landing, SHA-256 and optional S3 originals |
| `contracts.R`, `contract-tools.R` | Structure, keys, R rules, pointblank gates and contract review |
| `pipeline.R`, `input-gate.R`, `ingest-data.R` | Input checks, candidates, retries, publication and data-frame ingestion |
| `products.R` | Products and dm models based on pinned releases |
| `metrics.R` | Approved metrics and report manifests |
| `dbt.R`, `dbt-init.R`, `dbt-publish.R` | dbt configuration, CLI execution, artifacts and explicit snapshot publication |
| `registry.R` | Versioned definitions, releases and additive metadata migration |
| `diagnostics.R`, `quality-reports.R` | Shared inspection and quality report exports |
| `delivery-monitor.R`, `maintenance.R` | Expected deliveries and cleanup of unpublished failed-run tables |
| `catalog.R` | Freshness information and a read-only Shiny app |
| `adapters.R` | Explicit YAML exports and capability declarations |

## Publication transaction

An immutable candidate is materialized and checked before publication. Only
approved candidates receive a `releases` entry. That marker, the corresponding
lineage and `runs.status = published` are written in one transaction in the same
lake. Failure before commit leaves no newly visible release. Failure after
commit leaves a discoverable release that a retry can reuse.

`dl_tbl()` resolves published releases. Direct SQL can still access Raw data and
rejected candidates. The quality gate enforces the framework's publication
process; storage access permissions remain a separate responsibility.

Immutability means that the framework API does not overwrite published tables.
Administrators and direct SQL clients with write credentials can still alter
those tables.

## Quality semantics

| Result | Publication |
|---|---|
| `passed` | Allowed |
| `warning` | Allowed; the release retains warning quality |
| `failed` | Blocked |
| `error` | Blocked, including errors in otherwise non-blocking business rules |
| `not_checked` | Blocked |

For `policy = "rule"`, failure ratio and severity determine tolerance.
For `policy = "agent"`, evaluated native pointblank action levels determine the
gate outcome. Results retain segment, stage and threshold metadata. Inactive
steps and empty plans do not count as passes. There is no automatic row removal
or general force-publication switch.

## Version identities

* Definition: asset ID, version and fingerprint.
* Original: SHA-256 of the archived bytes.
* Run: its own ID and start/end times.
* Release: its own ID, candidate table, contract version and predecessor.
* Product: recorded input release IDs.
* Metric: definition version, input release, parameters and result hash.
* Report: a fixed combination of metric manifests and result values.

A source receiving a newer release does not automatically rebuild its products.
The operating project's scheduler controls the next `dl_build()` call.

## Operating model

Registry operations require exactly one coordinated writer. The local backend
is intended for a single writing process. A shared PostgreSQL deployment still
needs a locking/uniqueness strategy before concurrent publication is supported.
Checking a previously read parent release detects changes already committed by
another run; it does not provide a distributed lock between active transactions.

The catalog app can use an exported snapshot without holding a write connection.
Snapshot time and data age are shown separately. Metadata exports omit report
values but can include business descriptions, contacts, source filenames and
paths. Distribute them according to the operating project's access rules.

## Extension priorities

1. Verify PostgreSQL/S3 integration in the target environment and serialize
   writer execution in the operating project.
2. Connect an existing notification transport and monitor delivery failures.
3. Store partition corrections incrementally instead of copying the full state.
4. Define retention and restoration rules that include report evidence.
5. Publish related tables within an explicitly defined shared transaction.
6. Verify adapters against the specific external metadata schema versions used.

The [design review](DESIGN_REVIEW.md) explains how these extensions fit the
framework's composition principles. Adding more storage backends should follow
clear use cases and a stable core interface.
