# Modern data stack requirements and Ab Initio comparison

This is a capability assessment, not a performance benchmark or a claim of
enterprise-platform equivalence. The scope is an R-first framework that combines
existing tools. A working adapter is distinct from an operated production service.
Consult [the validation record](VALIDATION.md) for verified environments.

## Requirements and implementation boundaries

| Requirement | tidyweave implementation | Boundary or remaining responsibility |
|---|---|---|
| Small first workflow | `product()`, `add_source()`, `run()`, `collect()` | An R session and core dependencies suffice. |
| Multiple sources | Named sources and nested product dependencies | Cross-system joins need an explicit placement/materialization choice. |
| Files and APIs | CSV/TSV/RDS, optional Excel, Arrow/Parquet, httr2 requests and bounded pagination | Authentication, rate policy and API-specific parsing remain configured in the existing client. |
| Database connectivity | DBI sources and targets; caller connections or factories | Install the relevant DBI/ODBC driver. HANA/PostgreSQL support is through DBI, not a claim that every driver was tested. |
| Logical access and pushdown | Lazy DBI/dbplyr tables and Arrow queries | Arbitrary R functions and some targets materialize data. No federated query optimizer is implemented. |
| Transformations | Ordinary R functions, SQL escape hatch and staged dbt models | dbt owns its graph, tests and incremental materializations. |
| Contracts | Types, required fields, keys, business rules, optional ownership/version metadata and schema differences | Semantic compatibility still needs human judgment. |
| Quality | Native predicates, reference checks and optional pointblank | Quality thresholds express policy; sampling is not proof of every row. |
| Profiling | Aggregate column summaries | Profiling is not automatic anomaly detection or PII classification. |
| Durable publication | DuckDB/DuckLake releases; optional DBI, Parquet and pins targets | Only lake targets provide the package's immutable-release lifecycle. Other guarantees are adapter-specific. |
| Incremental work | Partition replacement for lakes; dbt incremental models; targets caching | Generic change-data capture and stream checkpointing are outside the package. |
| Dependency execution | Direct product dependencies or optional targets | Use an external runner for schedules, resource allocation and process-level recovery. |
| Operational evidence | Run history, quality incidents and structured metadata | Evidence does not itself provide alert routing, uptime monitoring or an incident-management service. |
| Metadata and lineage | Local registry, buffered OpenLineage events and OpenMetadata table upserts/mapped table lineage | No universal column-level lineage inference; remote catalogs must already be operated. |
| Reproducible reports | Pinned releases, metrics and report manifests | External side effects and live API state need their own reproducibility strategy. |
| Environment reproducibility | Project templates and optional renv bootstrap | Pin and restore infrastructure, credentials and external engine versions separately. |
| Deployment | Runnable R/targets projects and Connect document template | CI/CD and Connect perform deployment/scheduling; tidyweave does not provision servers. |
| Access and governance | Ownership metadata; credentials stay in clients/environment | Authorization, row policies, masking, secrets and access reviews belong to infrastructure and governance tools. |
| Reliability | Fail-closed quality, lake transaction tests and retryable catalog delivery | No distributed transaction spans databases, files, pins and catalogs. |
| Extensibility | S3 read, transform, quality, write, metadata and capability methods | Adapter authors own compatibility and their backend's guarantees. |

These requirements are design criteria for a modern stack, not a claim that every
project needs every capability. Start with the smallest useful workflow and add
the operational responsibilities justified by its importance.

## Comparison with Ab Initio

Ab Initio's published portfolio covers distributed processing, graphical
development, operational orchestration, real-time processing, metadata, quality,
matching and test-data management. The following comparison uses those vendor
descriptions, not hands-on evaluation of licensed products.
[Ab Initio product list](https://www.abinitio.com/en/product-list/).

| Capability area | Ab Initio portfolio reference | Position of tidyweave |
|---|---|---|
| Processing and scale | Co>Operating System | R/SQL composition backed by existing engines; no distributed runtime of its own. |
| Graphical authoring | GDE and Express>It | Code-first R API and inspection; no visual application editor. |
| Automation and operations | Conduct>It and Control>Center | targets/CI/Connect integration plus run evidence; no integrated enterprise control centre. |
| Streaming | Continuous>Flows | Batch workflows; streaming deliberately delegated to specialist platforms. |
| Catalog and governance | Enterprise Meta>Environment | Local operational registry and external catalog adapters; narrower coverage. |
| Querying | Query>It | DBI/dbplyr and backend SQL; no built-in cross-system federation service. |
| Quality | Data Quality Environment | Contracts, pointblank, reference checks, profiles and incidents; no full stewardship application. |
| Entity matching | Co>Relate | No dedicated matching engine. An external implementation can be called as a transform. |
| Test-data management | TDM | Synthetic example projects; no referential masking or test-data management platform. |

The useful architectural inspiration is composable processing with metadata,
quality and operational visibility. The package's implementation choice is a
small R interface and replaceable ecosystem components. Ab Initio explicitly
describes a broader integrated graphical and distributed architecture.
[Architectural principles](https://www.abinitio.com/en/architecture/).

## Deliberately deferred

A distributed streaming engine, graphical ETL editor, entity-resolution engine
and enterprise IAM would each become a substantial separate product. Building
them inside this package would work against its lightweight purpose. Tag-based
authorization, live masking, CDC, semantic discovery and end-to-end disaster
recovery remain infrastructure/integration work, not implied features of a
catalog adapter. Ab Initio advertises broader catalog and governance coverage.
[Catalog, quality and governance](https://www.abinitio.com/en/data-catalog-quality-governance/).
