# Validation record for tidyweave 0.8.0

Checked on 20 September 2026 with R 4.3.3 on Ubuntu 24.04. All data and HTTP
service fixtures were synthetic. This is a development version, not a stable
release candidate.

## Executed checks

| Check | Result |
|---|---|
| Full source build and `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| Installed package test suite, DuckDB default | 933 passed expectations; no failures, warnings or skips |
| Complete source suite, DuckLake default | 176 tests; 930 passed expectations, no failures or warnings; one installed-worker test skipped here and passed in the package check |
| Installation with hard dependencies only | Native workflow, contracts, quality, metadata and missing optional-backend preflight passed |
| Documentation | All 12 vignettes built, extracted R scripts executed and outputs rebuilt in the package check |
| Minimal installed workflow | Ordinary table to checked product to tibble passed |
| Advanced installed workflow | SQLite to Parquet to versioned pins, quality gates, metadata callback and four durable run records passed |
| Extension and history walkthroughs | Custom source/target/quality, named dependencies, corrections and pinned reports executed successfully |
| Optional execution engines | Actual dbt builds/tests, pointblank, Arrow, targets and a separate installed-package R worker exercised |
| Documentation website | Fresh pkgdown build: 81 help topics, 12 articles; no missing local links or anchors; search index and sitemap verified |
| Diagrams | SVGs rasterized and visually inspected |

## Integrity and interchangeability

Regression tests cover additive named sources, duplicate-name errors, cycles,
shared upstream execution, backend substitution, lazy DBI and Arrow boundaries,
connection ownership, and preflight before data acquisition. Contracts cover
factors, list columns, missing logical results, explicit freshness and exact
integers above 2^53.

Database targets validate the actual stored candidate inside the transaction.
Tests reproduce cast-induced duplicate keys, confirm append and replacement
rollback, and reject unsafe DuckDB BIGINT read modes. Lake checks retain complete
candidate validation, original archives, pinned releases and quality evidence.
Acquisition/combination failures create durable failed runs. Runtime input IDs
remain separate from immutable product definitions, including targets execution.

HTTP fixtures exercise API pagination and retry, OpenMetadata requests and
OpenLineage events. Payloads were also checked against official JSON schemas.
Catalog outages retain pending delivery records; retries do not rerun successful
data transformations. Evidence excludes row values and credential-bearing URLs.

## Tested components

DuckDB 1.5.5, Arrow 25.0.1, pointblank 0.12.4, pins 1.4.2, targets 1.12.0,
httr2 1.3.0, RSQLite 3.53.3 and webfakes 1.5.0 were available locally.
External dbt tests used dbt-core 1.12.5 and dbt-duckdb 1.10.1 with telemetry
disabled. Project templates include optional renv and Posit Connect entry points;
a generated template is not evidence of a Connect deployment.

## Verification boundaries

Local fixtures do not establish production connectivity to PostgreSQL, HANA,
S3, OpenMetadata or an OpenLineage service. They do not prove distributed locking,
transactional DDL on every DBI driver, multi-destination atomicity, continuous
streaming or workloads larger than memory. Lazy transformations depend on backend
support. Lake publication deliberately materializes a complete candidate.

Data publication, local evidence and remote catalog delivery are separate
operations. Catalog delivery is at least once. Local lake and evidence writes
require one coordinated writer. Custom adapters retain responsibility for their
own persistence guarantees.

GitHub Actions defines Linux DuckDB/DuckLake checks, R 4.2.3 compatibility,
Windows/macOS checks and a core-only installation. A configured job is not a
passing result: consult [Actions](https://github.com/JanWein/tidyweave/actions)
for evidence tied to the published commit. Earlier validation records remain in
git history and describe their respective older versions.
