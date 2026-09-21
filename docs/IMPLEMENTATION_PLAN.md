# tidyweave development plan

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


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

The main grammar is tw_product(), tw_add_source(), tw_add_transform(), tw_add_contract(),
tw_add_quality(), tw_set_target(), tw_add_catalog(), tw_validate(), tw_run(), tw_publish(),
tw_collect(), tw_inspect() and tw_explain(). No compatibility aliases for dl_* remain.
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
