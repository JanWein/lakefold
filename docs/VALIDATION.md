# Validation record for tidyweave 0.11.0

Checked on 20 September 2026 with R 4.3.3 on Ubuntu 24.04. All deliveries and
HTTP fixtures were synthetic. This is a development version, not a stable
release candidate. The implementation was reviewed with the Posit
package-development, testing and critical-review skills.

## Executed checks

| Check | Confirmed result |
|---|---|
| Full source build and `R CMD check --no-manual` | 0 errors, 0 warnings; one worktree packaging note, corrected afterward as described below |
| Installed-package test suite, DuckDB with real optional integrations | 2,033 passed expectations; 0 failures, 0 warnings, 0 skips |
| Source test suite, DuckLake | 2,021 passed expectations; 0 failures or warnings; three optional/source-only skips covered by the installed-package check |
| Core-only installation without DuckDB | Passed native execution defaults, contract composition, source correction, metadata and zero-write failure gates |
| Public function examples | Passed in the installed-package check |
| Default vignettes | All 14 built; vignette scripts and rebuilt outputs passed package checks |
| Native product grammar | Focused dplyr, lookup, quality, result-source and targets tests passed |
| Interchangeable lookup engines | Native and dm tests passed, including compatible lazy database inputs |
| Complete insurance runner, DuckLake | Real dbt builds, checked staging products, mart publication, measures and report preservation passed |
| Insurance correction | January cash changed from EUR 980 to EUR 1,230; the issued original report and original release retained EUR 980 |
| Native examples | Generated composition and monthly scripts passed; the infrastructure-free insurance regression passed |
| Product and metric vignette | Full DuckDB/dm execution passed with no warnings after migration to the common publication grammar |
| Documentation reference | 90 help topics and 14 articles; `pkgdown::check_pkgdown()` passed with the everyday/integration/extension grouping |
| R documentation generation | Roxygen completed without warnings; generated help and usage passed the package check |

The full check included installed examples, all vignette scripts and rebuilding
vignette outputs. Its only note was the `.git` reference file of the isolated
worktree appearing in the source archive. `.Rbuildignore` now excludes that file.
A final packaging check passed with **0 errors, 0 warnings and 0 notes**, skipping
tests, examples and vignette execution already exercised above. All 247 R, test,
namespace, help and bundled-example files in the rebuilt archive are byte-identical
to the fully checked archive; Git metadata is absent. No GitHub CI or website
deployment was performed for this branch.

## Coherent workflow checks

Execution defaults are pure values. Engine defaults propagate through nested
products; explicit local engines win. Destination defaults apply only to the
root, so an intermediate lookup does not acquire an unintended publication.
Tests verify native/Pointblank and native/dm paths, invalid preflight, unchanged
definitions and writers not running after failed gates.

Contract updates require an explicit new identity or version and preserve the
original object. Tests cover optional added columns, removed required columns,
changed key types, changed grain and explicit rule review. Contract formulas and
product formulas share normalization. Automatic semantic inference through
arbitrary dplyr operations is deliberately absent.

Batch metrics distinguish per-period calculation from explicit aggregation.
Stock guards remain active. Tests cover grouping, exact release pinning,
Date-valued selections, labels and units in report identity, tampering, report
retries and roundtrips, and owned/borrowed connection cleanup. Corrections retain
existing product transformations and gates; unselected pinned releases remain
unchanged. Managed dbt source replacements remain connection-free definitions.
Result lineage uses recorded evidence, and normalized outcomes retain native
statuses, including blocked missing deliveries.

## Unified grammar integrity

The product remains one specification class. Supported dplyr methods defer real
expressions until execution; inspection does not read sources or evaluate those
expressions. Tests cover ordinary data masking, selection, grouping and external
bindings, plus deterministic definition inspection. `tw_collect()`, `tw_explain()`
and `tw_tbl()` reuse the dplyr generics rather than competing with them.

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
`tw_dbt_contract()` schema bridge. The final R mart gate keeps business rules and
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

## 0.12.0 everyday usability validation

This section records the 0.12.0 usability refactor separately. The 0.11.0
expectation counts and integration results above are historical evidence, not
results for this version. Checks use synthetic data. This is API and regression
verification, not an independent human usability study.

| Check | Confirmed result for 0.12.0 |
|---|---|
| R documentation generation | Roxygen completed cleanly |
| Documentation reference | `pkgdown::check_pkgdown()` passed |
| Vignettes | All 14 built, their scripts ran, and outputs rebuilt in the final check |
| Package static checks and public examples | Passed in the final `R CMD check` run |
| Final read-only implementation review | No remaining blockers identified |
| Full installed-package regression suite | 2,182 passed expectations; 0 failures, 0 warnings, 2 optional skips |
| Targeted real insurance integration | 89 passed expectations; 0 failures, 0 warnings, 0 skips |
| Extracted insurance runner | Passed in the installed suite; January cash changed from EUR 980 to EUR 1,230, while the original report retained EUR 980 |
| Final `R CMD check --no-manual` status | 0 errors, 0 warnings, 0 notes |

The two optional skips were the OpenMetadata CLI and Python SDK integration
checks because their environment variables were not set. The 0.11.0 historical
OpenMetadata results do not count as re-execution for 0.12.0. The final check
completed on 20 September 2026 and included installed tests, public examples,
vignette scripts and output rebuilding.

The implementation is published for review in [PR #13](https://github.com/JanWein/tidyweave/pull/13).
This local validation does not assert that its GitHub checks passed or that it
was merged.

The everyday tutorial now follows one definition through a trial, failed input,
publication, correction, comparison, related calculations and report readback.
The insurance tutorial uses named sources and shared metric definitions while
keeping receipt acceptance, enriched publication, dbt execution and the final
approved snapshot visible. These executable tutorials exercise the documented
path; they do not measure how quickly an unfamiliar user learns it.

### Numeric presentation and report integrity

DuckDB can return whole-number aggregates as `integer64`, while other metrics
return R doubles. Mixed numeric measurement collection and numeric report
serialization guard the exact integer range from `-2^53` through `2^53` before
conversion. Values beyond this boundary are rejected where conversion would
otherwise risk losing integer precision. This safeguard does not make every
arithmetic operation exact, and it does not change the separate handling of
BIGINT identifiers in stored tables.

### Remaining operating and usability boundaries

A product with a configured destination can write when `tw_run()` executes. The
introductory trial uses an untargeted definition, and `tw_publish()` makes the
intent to persist explicit. Stored configuration is an ordinary value, not a
mutable global context.

Source replacement updates the known R product graph and preserves its checks;
it does not automatically execute a separate dbt project. Managed dbt source
bindings can be replaced explicitly at execution. dbt may write intermediate
models before a later test fails, and independent lake publications are not a
single distributed transaction.

Business keys, complete-table versus complete-partition delivery, stock-versus-
flow meaning and approval of metric definitions remain explicit decisions.
Exploration can omit approval and code version, but issued reports require
approved, versioned calculation definitions and retained source evidence.

One coordinated writer and sufficient memory for a complete lake candidate are
still required. Remote-storage connectivity, production deployment, distributed
locking and independent user testing are not established by these local checks.
GitHub CI status belongs to the exact published commit and is not implied by this
record.
