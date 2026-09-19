# Architecture in 0.7.0

## Why this architecture

lakefold combines a tidyverse-inspired external experience with structural
ideas from tidymodels: normalization, reusable specifications, composition,
validation, planning and interchangeable execution. It does not copy a modeling
API. Users see ordinary R objects and a few verbs; extension developers see
explicit interfaces.

The product definition describes **what** to read, prepare, check and publish.
Adapters determine **how** those operations use R, DBI, DuckDB, DuckLake,
pointblank, dbt or another existing tool. A product owns no platform services.

![Simple public verbs, structured preparation and interchangeable execution.](../vignettes/figures/composition-architecture.svg)

## Public grammar and normalization

| Task | Public function | Internal representation |
|---|---|---|
| Name the output | `dl_product("orders")` | Small `dl_product_spec` list |
| Supply input | `dl_add_source()` | Ordinary frame/function, file source or adapter |
| Prepare data | `dl_add_transform()` | Ordinary function; formulas become functions; explicit SQL adapter when needed |
| Describe expectations | `dl_add_contract()` | Existing `dl_contract`; named types or prototypes are normalized |
| Add checks | `dl_add_quality()` | Existing rules; formulas/functions become native rules |
| Choose storage | `dl_add_target()` | Folder/config/connection becomes a lake target; custom target passes through |
| Deliver metadata | `dl_add_catalog()` | Function or catalog adapter |
| Check intent | `dl_validate()` | Validated definition; no acquisition |
| Inspect the plan | `dl_plan()`, `dl_inspect()`, `dl_explain()` | Tibble, descriptive list, plain-language text |
| Execute | `dl_run()` | Existing S3 execution dispatch |
| Publish immediately | `dl_publish()` | Product with an explicit or default lake target |
| Get the table | `dl_collect()` | Ordinary tibble, pinned to its release for lake results |

There is no class for an ordinary R transformation, scheduler or global plugin
registry. Only components whose configuration has meaning become objects.
Contracts remain independently usable through `dl_validate(data, contract)`.
The latter returns evidence rather than replacing a data frame with a wrapper.

## Execution paths

The native executor reads a frame, applies ordered transformations, normalizes
or infers a contract, evaluates the quality gate, then calls the target writer.
With no target it returns data and evidence in memory. A custom writer receives
only checked data and owns its storage guarantees.

The lake executor compiles the same product to the existing ingestion pipeline.
It archives original files, or snapshots received frames, materializes raw data,
applies the shared transformation adapters, composes complete candidate state,
validates it and commits its release. Automatic output schemas are resolved
after transformations. The initial schema remains a persistent baseline, and
existing contracts or added rules cannot silently disappear through a later
unguarded write.

Composed transforms receive ordinary frames in both execution paths. Existing
`dl_pipeline()` and derived `dl_product(inputs, build, contract, ...)` calls
retain their lazy dbplyr semantics. This compatibility boundary avoids changing
established memory use and historical identities.

`dl_run(dl_dbt_project(...))` delegates to dbt's existing CLI lifecycle. dbt owns
its inputs, graph, connections and mutable model materializations.
`dl_dbt_publish()` snapshots a currently visible successful relation through the
shared lake publication gate. A historical invocation ID does not establish the
current bytes of a mutable dbt relation.

## Component extension interfaces

`dl_read_source()`, `dl_execute_transform()`, `dl_run_quality()`,
`dl_write_target()` and `dl_publish_metadata()` are S3 generics. Each component
also implements structural `dl_check_component()` preflight; `dl_inspect()` can
supply a safe description. A storage engine may specialize `dl_execute_target()`
when the default executor cannot express its transaction/resource semantics.

Extension methods register through their own package NAMESPACE. A user does
not need to modify core branching or install a central plugin registry.
Malformed quality results fail closed. There is no assumption that a custom
backend supports immutable releases, partition replacement or multiple writers.
The extension guide supplies a complete adapter and its guarantees.

## Dependencies and ownership

The core imports DBI, dbplyr, dplyr, tibble, rlang, digest and jsonlite. DuckDB,
pointblank, readxl, processx, dm, Shiny, YAML and S3 clients are optional.
Core table validation and native products do not require DuckDB. Lake storage
and `dl_sql()` check for it at the relevant integration boundary.

A DBI source accepts an open connection or factory. Only factory-owned
connections are closed by the source. A lake target closes only connections it
opens. Inspectable descriptors omit live connections and closure environments;
use versioned R project code for executable definitions and dependency locks.

## Lifecycle and metadata

Definitions have a lightweight defined/validated state. A run records the
validated and planned transition, start and finish, then completed, published,
cached, blocked or error. Preflight errors raise immediately without acquisition.
Run results contain an ID, status, timestamps, source/output descriptions,
quality, schema, row count, lineage and locally inspectable exceptions.

Native evidence is in memory. Lake ingestion/release evidence is in the existing
registry. Preflight and source-factory failures before ingestion starts remain
local. Catalog delivery happens after data publication; failure adds a warning
and cannot reverse a committed release. Catalog upserts should use stable
product/release identity for idempotence.

Composed products do not cache by default. Explicit caching requires a
`code_version` covering captured values, imported functions and dependencies.
Explicit product and contract versions remain immutable once registered.

## Package boundaries

| Module | Responsibility |
|---|---|
| `composition.R` | Product additions, normalization, preflight and inspection |
| `components.R` | Source/transform interfaces; DBI, file and SQL adapters |
| `execution.R` | Native execution, result evidence, target writer and catalog interfaces |
| `target-lake.R` | Compile composed products into governed lake execution |
| `quality-engine.R` | Quality dispatch and validated engine results |
| `contracts.R`, `contract-tools.R` | Existing contracts, schema/key checks and contract review |
| `pipeline.R`, `sources.R`, `registry.R` | Existing landing, candidates, atomic publication and durable evidence |
| `simple.R`, `ingest.R`, `ingest-data.R` | Existing immediate lake interfaces and local defaults |
| `products.R`, `metrics.R` | Pinned derived products, relational models, metrics and report manifests |
| `dbt*.R` | Existing dbt CLI, artifacts and snapshot publication |
| Inspection/operations modules | Quality reports, catalog UI, history, monitoring, recovery and cleanup |

These interfaces permit future adapter packages without splitting this package
prematurely. The review and migration guide explain the preserved boundaries.

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


## Read-only execution and metric identities

`read_only = TRUE` attaches persistent storage with DuckDB's `READ_ONLY` option,
skips directory creation and registry migration, and rejects write APIs before
input acquisition. The in-memory connection may still load required extensions.
Measurements default to no recording on this connection and carry the complete
metric definition in their result manifest. New transient metrics are allowed,
but an existing ID/version cannot be reused with a changed definition.

Formula identity uses the full deparsed expression, never a display label.
Closure environments are not serialized; explicit `code_version` remains the
contract for changed external values and dependencies. Identical report retries
ignore only calculation timestamps. Storage, definitions and semantic report
inputs remain versioned.

Registry schema 3 adds writer ownership for new runs. Linux recovery checks
host, boot and process start; unknown owners require explicit operator evidence
that the writer stopped. Recovery never infers abandonment solely from age.
