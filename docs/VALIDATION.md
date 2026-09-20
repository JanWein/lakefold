# Validation record for tidyweave 0.10.0

Checked on 20 September 2026 with R 4.3.3 on Ubuntu 24.04. All deliveries and
HTTP fixtures were synthetic. This is a development version, not a stable
release candidate. The final packaged check, documentation generation and
website audit have completed.

## Executed checks

| Check | Confirmed result |
|---|---|
| Final source build and `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| Installed-package test suite | 1,861 passed expectations; 0 failures, 0 warnings, 0 skips |
| Core-only installation without DuckDB | Passed native composition, quality, metadata and optional-target preflight |
| Public function examples | Passed in the installed-package check |
| Default vignettes | All 14 built; vignette scripts and rebuilt outputs passed package checks |
| Native product grammar | Focused dplyr, lookup, quality, result-source and targets tests passed |
| Interchangeable lookup engines | Native and dm tests passed, including compatible lazy database inputs |
| Complete insurance runner, DuckLake | Real dbt builds, checked staging products, mart publication, measures and report preservation passed |
| Complete insurance vignette, DuckLake | Rendered all infrastructure stages successfully; its final render log contained no errors or warnings |
| Insurance correction | January cash changed from EUR 980 to EUR 1,230; the issued original report and original release retained EUR 980 |
| Native examples | Generated composition and monthly scripts passed; the infrastructure-free insurance regression passed |
| Product and metric vignette | Full DuckDB/dm execution passed with no warnings after migration to the common publication grammar |
| Documentation website | 87 help topics, 14 articles and 145 HTML pages, including method redirects; no missing help topics, articles, local links or anchors; all 5 SVG files and the search index validated |
| R documentation generation | Final roxygen pass completed without warnings or additional generated changes |

## Unified grammar integrity

The product remains one specification class. Supported dplyr methods defer real
expressions until execution; inspection does not read sources or evaluate those
expressions. Tests cover ordinary data masking, selection, grouping and external
bindings, plus deterministic definition inspection. `collect()`, `explain()`
and `tbl()` reuse the dplyr generics rather than competing with them.

Checked lookups treat their references as execution dependencies. Native and dm
implementations enforce unique, non-missing parent keys and the declared policy
for unmatched child keys. Tests include composite keys, orphan children,
duplicate parents, shared dependencies, compatible lazy inputs and explicit
cross-backend limits. Pointblank and native logical predicates share failure
semantics; specialist agents remain an optional separate interface.

Successful lake results identify exact immutable releases. Other successful
results reuse their retained submitted data or lazy query, with the backend's
mutability; a DBI append result represents its submitted batch. Configuration
sources resolve one release and materialize through an owned read-only handle.
Tests cover catalog integrity, caller ownership, error cleanup and reuse of the
active execution lake when reading and publishing to the same store.

The local configuration shortcut creates no directories or connections while
being defined. Data-first ingestion accepts ordinary data or a product containing
one source and input checks. Invalid receipt configurations fail before source
callbacks or destination creation. Transformations belong in product preparation
and publication, after the receipt boundary.

## Layered and insurance workflow integrity

The layered integration uses CSV and Excel deliveries and a local HTTP API.
It checks raw/staging/core/marts schemas, model dependencies, dbt contracts and
exact source references. Native and Pointblank failures retain landing evidence
without writing accepted RAW tables or replacing prior releases. Readers and
business callbacks run once per uncached ingestion; the stored candidate retains
its structural, required-field and key checks.

The insurance workflow keeps policy-month observations and cash transactions
at separate grains. Checked lookups enrich them independently. dbt aggregates
them separately before joining company, channel and month. Regression assertions
cover multiple payments for one policy, unpaid and inactive groups, receipt-month
keys, reconciled totals and the preservation of independent staging releases.

Managed dbt execution prepares connection profiles and source bindings from the
selected releases. Tests retain explicit SQL models and the bounded
`dbt_contract()` schema bridge. The final R mart gate keeps business rules and
composite-key checks. Publication rejects unsuccessful selections or changed
invocation artifacts; dbt's mutable build relations are distinct from approved
immutable snapshots. Coordinate writers between build and publication.

Measurements use the approved lake result's exact release. Tests distinguish
single-date stocks from multi-period flows, calculate ratios from aggregate
numerators and denominators, and reject undefined ratios. Corrected reports use
new releases while earlier issued values and manifests remain readable.

Earlier coverage remains in the suite for DBI/Arrow/pins adapters, rollback and
stored-value gates, exact BIGINT identifiers, reference quality, cycles, durable
run evidence, catalog recovery, deterministic definitions and targets caching.

## Metadata verification and limits

The OpenMetadata adapter's tests use the official ingestion SDK to validate
configuration and an actual CLI process against a local HTTP fixture that
intentionally rejects ingestion. These exercise the process and recovery boundary;
they do not demonstrate a successful production catalog import.

Artifact integrity and invocation matching are checked before metadata execution.
Pending delivery can retry the same artifacts without rebuilding data. Credentials
stay in the process environment, temporary files are removed, and delivery failure
remains separate from a successful data result. OpenMetadata's dbt engine enriches
existing table entities, so database inventory ingestion remains a prerequisite.
A zero CLI exit is not proof of complete lineage. Remote delivery and local
receipt persistence are separate operations and can produce duplicate attempts.

## Tested components

The environment contains R and Python DuckDB 1.5.5, DuckLake extension
`d8a1881e`, dbt-core 1.12.5, dbt-duckdb 1.10.1, Pointblank 0.12.4, dm 1.1.2 and
openmetadata-ingestion 2.0.0.0 on Python 3.12. Optional R integrations include
Arrow 25.0.1, pins 1.4.2, targets 1.12.0, httr2 1.3.0, RSQLite 3.53.3 and
webfakes 1.5.0. External dbt telemetry was disabled.

## Verification boundaries

Local tests do not establish production connectivity to PostgreSQL, HANA, S3,
OpenMetadata or an OpenLineage service. They do not prove distributed locking,
transactional DDL on every DBI driver, multi-destination atomicity, streaming or
workloads larger than memory. Ingestion and lake publication materialize data;
lazy transformation support remains backend-dependent.

The managed profile path covers local DuckDB and DuckLake. Other dbt adapters
require explicit profiles and separate deployment verification. Captured R
environments and live external data can change between runs; cache identity is
not proof that arbitrary external state has stayed unchanged.

Shiny/Quarto and supported Power BI export patterns are documented. No production
app, semantic model, dashboard refresh, external scheduler or catalog server was
deployed. Custom adapters retain responsibility for their storage guarantees.

GitHub Actions defines Linux DuckDB/DuckLake, R 4.2.3, Windows/macOS and core-only
checks. Consult [Actions](https://github.com/JanWein/tidyweave/actions) for outcomes
tied to the published commit; this local record does not pre-approve a future CI
run. Older validation records remain in git history for their respective versions.
