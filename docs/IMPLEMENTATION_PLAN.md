# tidyweave development plan

This is a breaking development release. Compatibility starts with the first
stable release candidate. Preserve immutable lake releases, full-candidate
quality gates, transaction boundaries and pinned report inputs.

## Architecture

One product contains named sources, ordered transformations, an optional
contract, quality rules, one target and optional metadata destinations.
Ordinary R values are normalized at composition boundaries. A single source
reaches a transform as a table; multiple sources reach the first transform as
a named list. Duplicate source names require explicit replacement. Products
can be sources of other products, with cycle detection before execution.

The main grammar is product(), add_source(), add_transform(), add_contract(),
add_quality(), set_target(), add_catalog(), validate(), run(), publish(),
collect(), inspect() and explain(). No compatibility aliases for dl_* remain.
Optional adapters implement reading, transformations, quality, writing and
metadata. Lazy DBI execution avoids forced collection. Capabilities expose
materialization and storage guarantees. Run evidence and catalog delivery are
separate from data publication.

## Delivery checklist

- [x] Rename package, public API, classes, environment variables and URLs.
- [x] Unify product composition and execution, named sources and dependencies.
- [x] Preserve lazy execution and declare adapter capabilities.
- [x] Fix factor inference, predicate parity, contract normalization and defaults.
- [x] Implement DBI, Parquet/Arrow and pins adapters.
- [x] Implement httr2 API ingestion and cross-table quality checks.
- [x] Implement durable run evidence, incidents, profiles and delivery retries.
- [x] Implement OpenLineage and OpenMetadata HTTP adapters.
- [x] Integrate targets, dbt and project templates with renv and Connect.
- [x] Consolidate canonical executable English documentation and examples.
- [x] Document architecture rationale and modern-stack/Ab Initio comparison.
- [x] Verify core, optional integrations, examples and R CMD check.
- [x] Publish verified code and rename the GitHub project.

## Scope and verification

Do not build a distributed streaming engine, visual ETL editor, entity-resolution
platform, scheduler or enterprise IAM. Use existing ecosystem implementations.
Local HTTP fixture tests are not production-service deployment evidence.
The Posit implementation skill delegates code with exclusive file ownership.
Heavy integration suites run sequentially. The working environment restored an
older snapshot after an outage; restore and verify actual files before continuing.
