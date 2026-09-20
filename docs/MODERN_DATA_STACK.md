# Modern data stack requirements and Ab Initio comparison

This is a capability assessment, not a performance benchmark or a claim of
enterprise-platform equivalence. The scope is an R-first framework that combines
existing tools. A working adapter is distinct from an operated production service.
Consult [the validation record](VALIDATION.md) for verified environments.

The 0.9.0 development increment makes the batch path from receipt to consumer
explicit. `ingest()` accepts a delivery after optional input checks;
`dbt_sources()` binds that exact RAW release to a logical SQL source;
`dbt_build()` prepares staging, core and marts; `dbt_publish()` approves an
immutable consumer snapshot. The [layered tutorial](https://janwein.github.io/tidyweave/articles/layered-data-stack.html)
explains this path with ordinary R data before introducing infrastructure.

## Requirements and implementation boundaries

| Requirement | tidyweave implementation | Boundary or remaining responsibility |
|---|---|---|
| Small first workflow | `product()`, `add_source()`, `run()`, `collect()` | An R session and core dependencies suffice. |
| Multiple sources | Named sources and nested product dependencies | Cross-system joins need an explicit placement/materialization choice. |
| Files and APIs | CSV/TSV/RDS, optional Excel, Arrow/Parquet, httr2 requests and bounded pagination | Authentication, rate policy and API-specific parsing remain configured in the existing client. |
| Receipt and RAW acceptance | `ingest()` archives a delivery, runs optional native/pointblank checks before RAW and returns an exact immutable release reference | Inputs are materialized in R; this is batch ingestion, not streaming or CDC. Rejected landing evidence is retained. |
| Database connectivity | DBI sources and targets; caller connections or factories | Install the relevant DBI/ODBC driver. HANA/PostgreSQL support is through DBI, not a claim that every driver was tested. |
| Logical access and pushdown | Lazy DBI/dbplyr tables and Arrow queries | Arbitrary R functions and some targets materialize data. No federated query optimizer is implemented. |
| Transformations | Ordinary R functions, SQL escape hatch and staged dbt models | dbt owns its graph, tests and incremental materializations. |
| Layered SQL preparation | Explicit raw/staging/core/marts starter; `dbt_sources()` binds accepted RAW releases without rewriting model SQL | The canned starter is an orders example. Design business models in normal dbt files; configure remote profiles separately. |
| Contracts | Types, required fields, keys, business rules, optional ownership/version metadata and schema differences | Semantic compatibility still needs human judgment. |
| R/dbt schema bridge | `dbt_contract()` exports SQL column types, supported key/null tests and schema enforcement properties | R predicates, pointblank, composite keys and R lifecycle policies are not automatically translated. Unsupported rules are explicit. |
| Quality | Native predicates, reference checks and optional pointblank | Quality thresholds express policy; sampling is not proof of every row. |
| Profiling | Aggregate column summaries | Profiling is not automatic anomaly detection or PII classification. |
| Durable publication | DuckDB/DuckLake releases; optional DBI, Parquet and pins targets | Only lake targets provide the package's immutable-release lifecycle. Other guarantees are adapter-specific. |
| Consumer approval | `dbt_publish(config, result, model)` snapshots a successful selected model; `collect()` returns the approved data | dbt data tests run after materialization. Earlier model writes are not rolled back; coordinate writers between build and snapshot. |
| Incremental work | Partition replacement for lakes; dbt incremental models; targets caching | Generic change-data capture and stream checkpointing are outside the package. |
| Dependency execution | Direct product dependencies or optional targets | Use an external runner for schedules, resource allocation and process-level recovery. |
| Operational evidence | Run history, quality incidents and structured metadata | Evidence does not itself provide alert routing, uptime monitoring or an incident-management service. |
| Metadata and lineage | Local registry, buffered OpenLineage, OpenMetadata table upserts, and optional official OpenMetadata Python ingestion of dbt artifacts | dbt model/test/SQL lineage interpretation belongs to the ingestion engine. Matching server, database service and table inventory are external prerequisites; there is no universal column-lineage guarantee. |
| Catalog recovery | Metadata delivery has its own receipt and retry status; `publish_metadata()` can retry unchanged dbt artifacts without rebuilding | Remote delivery is separate from data success. An interruption before local receipt persistence can repeat a delivery. |
| Reproducible reports | Pinned releases, metrics and report manifests | External side effects and live API state need their own reproducibility strategy. |
| R and BI consumption | Ordinary tables for Shiny/Quarto; approved data can be exported through DBI or Parquet | No native Power BI connector, semantic-model provisioning or managed report refresh is supplied. Use supported consumer connectors and hosting. |
| Environment reproducibility | Project templates and optional renv bootstrap | Pin and restore infrastructure, credentials and external engine versions separately. |
| Deployment | Runnable R/targets projects and Connect document template | CI/CD and Connect perform deployment/scheduling; tidyweave does not provision servers. |
| Access and governance | Ownership metadata; credentials stay in clients/environment | Authorization, row policies, masking, secrets and access reviews belong to infrastructure and governance tools. |
| Reliability | Fail-closed quality, lake transaction tests and retryable catalog delivery | No distributed transaction spans databases, files, pins and catalogs. |
| Extensibility | S3 read, transform, quality, write, metadata and capability methods | Adapter authors own compatibility and their backend's guarantees. |

These requirements are design criteria for a modern stack, not a claim that every
project needs every capability. Start with the smallest useful workflow and add
the operational responsibilities justified by its importance.

## Consumer and metadata boundaries

A built mart and an approved snapshot answer different questions. A mart is the
current output of a SQL model. An immutable release identifies the data that
passed the configured publication policy. A dashboard should consume that release
or its approved export when failed later builds must not affect its inputs.
An inferred publication contract covers structure, not undisclosed business rules.

Shiny accepts ordinary R data, and Quarto can render static reports or use a
Shiny runtime for interactive applications. Power Query supports Parquet at its
documented locations and ODBC through a configured driver. Those are ecosystem
consumption paths, not a claim that tidyweave deploys the consuming applications.
[Shiny tables](https://shiny.posit.co/r/components/outputs/table/),
[Quarto dashboards](https://quarto.org/docs/dashboards/),
[Power Query Parquet](https://learn.microsoft.com/en-us/power-query/connectors/parquet),
[Power Query ODBC](https://learn.microsoft.com/en-us/power-query/connectors/odbc).

The dbt catalog adapter delegates artifact interpretation to OpenMetadata's own
ingestion engine. Local CLI/configuration tests establish the adapter boundary;
they do not establish a live remote deployment. Each installation must verify
service names, existing table identities, credentials and server/engine versions.
New RAW release tables need database-inventory ingestion before dbt metadata can
attach to them. A successful metadata CLI exit is not a completeness check for
all expected lineage edges. Custom callbacks or S3 adapters can replace this hook.
The server remains responsible for its permissions, ownership workflows and UI.
[OpenMetadata dbt workflow](https://docs.open-metadata.org/v2.0.x/connectors/database/dbt/run-dbt-workflow-externally).

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
