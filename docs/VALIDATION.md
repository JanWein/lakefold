# Validation record for tidyweave 0.9.0

Checked on 20 September 2026 with R 4.3.3 on Ubuntu 24.04. All deliveries and
HTTP fixtures were synthetic. This is a development version, not a stable
release candidate.

## Executed checks

| Check | Result |
|---|---|
| Full source build and `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| Installed package test suite | 1,416 passed expectations; no failures, warnings or skips |
| Documentation | All 13 vignettes built; their R scripts and rebuilt outputs passed package checks |
| Public function examples | Passed in the installed-package check; generated help and S3 signatures are consistent |
| Complete layered integration, DuckDB | 78 expectations passed; two successful builds and one intentionally failed dbt build |
| Complete layered integration, DuckLake | The same 78 expectations passed with the interchangeable lake backend |
| Installed complete example | DuckLake, pointblank, source rebinding, immutable publication and pinned Parquet export passed; correction changed revenue from 150 to 175 while the old release remained 150 |
| OpenMetadata adapter | Official SDK configuration/schema validation, TLS handling and actual CLI execution against a local rejecting HTTP fixture passed |
| Metadata extensibility | Ordinary callbacks and custom S3 adapters used the same dbt execution hook |
| Documentation website | Fresh pkgdown build: 85 help topics, 13 articles and 126 HTML pages; no broken local links or anchors; search index, sitemap and 0.9.0 version verified |
| R documentation generation | A final roxygen pass produced no warnings or uncommitted reference changes |

## Layered workflow integrity

The integration test reads a CSV delivery, an Excel correction and a local HTTP
API response. It checks the physical raw/staging/core/marts schemas, generated
model dependencies, dbt contract enforcement, and the exact RAW table, asset,
run and release identity recorded in each manifest. Named logical sources remain
stable while their accepted physical references change explicitly.

Native and pointblank input failures retain landing evidence and write no new
RAW table or release. Repeated readers and business callbacks are evaluated once
per uncached ingestion. Inferred-schema failures occur before RAW persistence;
stored candidates still receive structural, required-field and key checks.
Original local file bytes and pinned source provenance are retained.

A failed downstream dbt test deliberately leaves a changed mutable mart, but
cannot replace the approved consumer release. Publication checks also cover
changed live relations, current-invocation selection, inferred structural
contracts, automatic definition versions, and exact immutable output references.
The build-to-publication interval still requires coordinated writers.

Configuration-based release sources read through owned read-only connections,
resolve one release, collect and close. Tests verify unchanged source-catalog
bytes, preserved lineage through DBI exports, old pinned releases, error cleanup,
and safe connection reuse when source and target share a lake. Caller-owned
sources remain lazy; custom source subclasses keep their S3 dispatch.

The full suite also retains earlier coverage for ordinary R composition, named
dependencies, cycles, interchangeable DBI/Arrow/pins adapters, reference quality,
exact BIGINT values, stored-value transaction gates, rollback, run evidence,
OpenLineage, catalog recovery, deterministic definitions and targets caching.

## Metadata verification

The official OpenMetadata ingestion SDK validates the generated workflow and dbt
configuration. An actual `metadata ingest` process reaches a local HTTP fixture
and reports its intentional rejection as a sanitized pending delivery, leaving
the successful dbt result unchanged. These checks exercise the process boundary;
they are not a successful production catalog import.

Tests reject missing, changed and mismatched-invocation artifacts before metadata
execution. Pending attempts retry the same invocation without rebuilding dbt.
Successful receipts are reused by default; explicit `force = TRUE` supports
redelivery after inventory refresh. Credentials remain in the child environment,
CLI output is discarded, temporary files are removed, and receipts retain no
fixture token. TLS assertions verify the SDK's default certificate-checking path.

OpenMetadata's dbt engine enriches existing table entities. Newly created RAW
release and model tables require database-inventory ingestion first. A zero CLI
exit is not evidence that every expected lineage edge was found. Remote delivery
and local receipt persistence are separate operations, with possible duplicates
if a process stops between them.

## Tested components

DuckDB 1.5.5 in R and Python, DuckLake extension `d8a1881e`, dbt-core 1.12.5,
dbt-duckdb 1.10.1, pointblank 0.12.4, and openmetadata-ingestion 2.0.0.0 on
Python 3.12 were exercised. Arrow 25.0.1, pins 1.4.2, targets 1.12.0,
httr2 1.3.0, RSQLite 3.53.3 and webfakes 1.5.0 were available for the full suite.
External dbt telemetry was disabled.

## Verification boundaries

Local tests do not establish production connectivity to PostgreSQL, HANA, S3,
OpenMetadata or an OpenLineage service. They do not prove distributed locking,
transactional DDL on every DBI driver, multi-destination atomicity, streaming or
workloads larger than memory. Ingestion and lake publication deliberately
materialize data. Lazy transformations depend on backend support.

Shiny/Quarto and supported Power BI export patterns are documented. No production
app, semantic model, dashboard refresh or external scheduler was deployed. Custom
adapters and external services retain responsibility for their own guarantees.

GitHub Actions checks Linux with DuckDB/DuckLake, R 4.2.3, Windows/macOS and a
core-only installation. Consult [Actions](https://github.com/JanWein/tidyweave/actions)
for results tied to the published commit. Earlier validation records remain in
git history and describe their respective older versions.
