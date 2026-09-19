# Design review: simple composition for complex data workflows

Review of lakefold 0.5.0, 19 September 2026.

## Purpose and design goal

lakefold is an independent, modular R framework for governed data workflows.
Its purpose is to make complex ingestion, validation, transformation, publication
and reporting tasks accessible through a small set of reusable building blocks.
Ease of use means that a short workflow is easy to start, while a larger workflow
can introduce explicit steps without changing its underlying concepts.

The framework has its own domain objects: sources, contracts, pipelines,
products, metrics and releases. It uses established R data structures and lets
specialist tools perform the work they already support. DuckDB/DuckLake store
and query data; dbt builds SQL models; pointblank evaluates quality rules; dm
represents declared relationships. lakefold connects their lifecycles and
records publication evidence.

## Principles that guide the interface

| Principle | Current implementation | Boundary |
|---|---|---|
| Start with a concise operation | `dl_open()`, `dl_write()` and `dl_read()` cover the minimal local workflow | Source-specific acquisition can still require ordinary R code |
| Compose when complexity grows | Explicit landing, extraction, precheck, transformation, validation and publication steps | A pipeline describes one ingestion workflow |
| Define before executing | Configuration and specification objects can be constructed without opening connections | External resources are checked during execution |
| Inspect the work | Compact print methods and `dl_plan()` reveal definitions and step order | A structural plan does not execute SQL or validate source data |
| Execute consistently | `dl_execute()` accepts pipelines, products, metrics and dbt projects | Each operation retains its own result type and lifecycle |
| Inspect results consistently | Status, quality, release and lineage accessors | Metric results also carry their own reproducibility manifest |
| Reuse familiar tools | Ordinary R callbacks, tibbles, dbplyr lazy tables, pointblank and dm | There is no general stable plugin protocol for every backend and source |
| Make publication explicit | Validate a candidate before recording its release | Registry writes require one coordinated writer |
| Keep complexity visible when needed | Contracts, version identities and input releases remain inspectable | Runtime credentials and scheduling belong to the operating environment |

A generic framework should offer reusable concepts across use cases. It should
also make the supported composition rules clear. Adding functions to a list or
using a pipe is insufficient: predictable inputs, explicit outputs, resource
ownership, consistent failures and useful documentation are part of the design.

## How users move from a small task to a larger workflow

1. Open a local folder with `dl_open()` and write data with `dl_write()`.
2. Add a contract or custom configuration only when the workflow needs it.
3. Introduce an explicit pipeline when input gates or named transformations are
   needed. The same validation and publication rules still apply.
4. Build derived products from named, pinned input releases. Reuse ordinary
   dplyr operations inside the builder.
5. Add metrics and report manifests when results need reproducible definitions
   and provenance.
6. Use dbt for SQL model dependencies and its own materializations. Explicitly
   snapshot and validate a relation with `dl_dbt_publish()` when a governed
   release is required.

The package should support this progression without requiring users to adopt
all integrations at once. Optional components remain optional, and the local
DuckDB path provides an entry point without remote infrastructure.

## Capabilities added in 0.4.0

| Need | Implementation |
|---|---|
| Validate before Raw writes | `input_contract` and `dl_step_precheck()` preserve the landed original |
| Respect graded quality decisions | Native pointblank action levels with `policy = "agent"` |
| Preserve small-segment evidence | Separate results for each pointblank segment |
| Export evidence and test the gate | HTML/JSON reports, native pointblank reports and `dl_expect_quality()` |
| Accept existing R data | `dl_ingest_data()` archives an immutable RDS snapshot and uses the existing cache |
| Draft contracts for review | Type inference, explicit confirmation and a change comparison |
| Record responsibility and meaning | Operator metadata, column descriptions and units |
| Inspect without registry internals | Shared status/quality accessors, release history and recursive dataset lineage |
| Reproduce a dbt output | Copy, validate and publish one current relation |
| Detect a delivery that never started | Business-date and deadline monitoring with notification deduplication |
| Reuse existing registry metadata | Additive migration to schema version 2 |
| Remove failed intermediate tables | Preview and cleanup while retaining release history and evidence |

## Where the framework works well today

The current implementation provides a usable core for local, coordinated data
workflows. It preserves originals, validates complete publication candidates and
computes metrics from recorded input releases. API users can inspect the
objects and results directly in R. The tutorials explain the common paths and
make external integration requirements explicit.

A successful dbt invocation has distinct guarantees from a lakefold release.
Each invocation receives an isolated artifact directory. Manifest and results
must share an invocation ID, and failures are checked through both process and
node outcomes. Primary and foreign keys are declared explicitly for dm; a SQL
dependency graph cannot establish them.

## Remaining priorities

| Priority | Capability | Next concrete step |
|---|---|---|
| High | Verify intended remote infrastructure | Exercise S3/PostgreSQL, restart, backup and restore in the target environment |
| High | Support larger inputs efficiently | Add database-side readers with explicit snapshot and fingerprint semantics |
| High | Improve changes to definitions | Provide documented update/remove helpers alongside contract comparisons |
| High when multiple writers are required | Coordinate concurrent publication | Introduce locking or uniqueness guarantees and conflict tests |
| Medium | Compose multiple products in execution order | Define an optional scheduler adapter using release fingerprints and cycle checks |
| Medium | Generalize first-class sources | Specify snapshots, repeatability, fingerprints and runtime credentials for database/API sources |
| Medium | Publish related tables together | Define a multi-table transaction boundary and relational quality gate |
| Medium | Add incremental ingestion | Specify keys, deletions and correction semantics before append/upsert support |
| Medium | Manage the full retention lifecycle | Track references from reports and releases, then define preview and restore behavior |
| Later | Broaden external metadata integrations | Add versioned target schemas and end-to-end adapter tests |

Priority depends on the deployment. A locking strategy is required before
concurrent production writers are introduced. Current migration and conflict
checks do not supply that coordination. The [feature overview](https://github.com/JanWein/lakefold/blob/main/docs/FEATURES.md)
distinguishes implemented behavior from these extension points.

## Responsibilities that remain with the surrounding platform

Scheduling, identity, access control, secrets and notification transport belong
to existing platform services. Standard transformations remain ordinary R or SQL
operations. A visual ETL editor and automatic column lineage for arbitrary R
code are outside the current scope.

`approved = TRUE` records a declared approval state; it does not implement a
review workflow. API immutability does not protect tables from direct SQL writes.
On the explicit API, `code_version` must cover changed closure values and
dependencies as well as function bodies. `dl_write()` re-evaluates custom
callbacks by default; supplying a code version opts into cache reuse. Calling `collect()` can bring large datasets into R memory.
Even metric calculation registers definitions and lineage, so it participates
in writer coordination.

## Design evolution

| Version | Main contribution |
|---|---|
| 0.1.0 | File ingestion, contracts, immutable releases, products, metrics and catalog |
| 0.2.0 | Connection-free configuration, inspectable plans, named transformations and a common execution entry point |
| 0.3.0 | dbt project specifications, isolated invocations, diagnostics and native lazy dm models |
| 0.4.0 | Input gates, richer pointblank evidence, shared diagnostics, contract tooling, explicit dbt publication and operational helpers |
| 0.5.0 | Minimal open/write/read workflow, optional metadata and automatic structural schemas and versions |

These changes extend the framework's own data workflow concepts. Future work
should be judged by whether it makes real workflows easier to compose, inspect,
operate and reproduce.
