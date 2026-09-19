# Validation record for lakefold 0.4.0

Check date: 19 September 2026. Local environment: Ubuntu 24.04 and R 4.3.3.

| Check | Result |
|---|---|
| Full `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| Expectations in the final local package check | 263 passed, 0 failed, 0 warnings, 0 skipped |
| Separate full DuckLake run | Passed, including actual dbt execution and snapshot publication |
| Examples and vignettes | All package examples checked; seven vignettes built and executable R chunks run |
| API and reference | 62 exported functions, 52 help topics, complete pkgdown index |
| Tests | 56 test cases, including quality gates, migration, reports and dbt publication |

GitHub workflows additionally check published commits with R 4.5.1 on DuckDB
and DuckLake, then build and deploy the website. See
[GitHub Actions](https://github.com/JanWein/lakefold/actions) for results tied to
a particular commit. Local results and GitHub results are separate evidence.
The documentation-language update does not change the runtime API.

## Behavior covered by the new checks

* Native pointblank thresholds warn or block per segment, preserving evidence
  that a global failure ratio could hide.
* Missing action levels, inactive checks and evaluation errors block publication.
* All present blocking columns (`S`, `E` and `C`) are evaluated together.
  Eight report layouts cover this behavior.
* A failed input gate retains landing evidence and the old release while
  preventing a new Raw table. The final candidate gate remains active.
* Data-frame ingestion preserves date types and reuses identical deliveries
  through the existing cache.
* Quality reports show the gate decision, escape HTML and omit failed-row
  extracts and samples.
* Contract drafts require explicit confirmation. Comparisons identify structural
  restrictions and changes that need semantic review.
* Diagnostic accessors distinguish the latest attempt, a pinned release and
  cache provenance. dbt process failures remain visible even when nodes pass.
* dbt relations are copied and validated afresh. Later relation changes do not
  modify a previously published release.
* Missing business dates can be detected without an import attempt. Successful
  notifications are deduplicated; transport failures remain retryable.
* Additive registry migration retains old evidence, is idempotent and rejects
  unknown newer schemas.
* Cleanup defaults to a preview and retains published tables and quality evidence
  when eligible intermediate tables are actually removed.

Tested core combination: DuckDB 1.5.5 in R and Python, pointblank 0.12.4,
dbt-core 1.12.5, dbt-duckdb 1.10.1 and dm 1.1.2. dbt telemetry is disabled.
Production S3, PostgreSQL, dbt v2/Fusion, concurrent writers, Windows/macOS and
sustained load testing remain outside the verified environments.

## Historical record: 0.3.0

Check date: 19 September 2026. Ubuntu 24.04, R 4.3.3.

| Check | Result |
|---|---|
| Full DuckDB suite | Passed without test failures or warnings |
| Full DuckLake suite | Passed without test failures or warnings |
| Actual dbt integration on both backends | Build, five dbt data tests, a separate test invocation and a dm query passed |
| `R CMD build` including vignettes | Successful |
| `R CMD check --no-manual` | 0 errors, 0 warnings, 0 notes |
| R examples and six vignettes | Executed or rebuilt in the package check |
| `pkgdown::check_pkgdown()` | No issues; complete reference index |
| `pkgdown::build_site()` | Full website, reference and articles built |

Version 0.3.0 defined 38 test cases. The final local check with dbt integration
enabled passed 165 expectations without failures, warnings or skipped tests.
An additional run without the external CLI passed 161 expectations and skipped
exactly the opt-in integration test.

The integration used dbt-core 1.12.5, dbt-duckdb 1.10.1 and DuckDB 1.5.5 in both
Python and R, with telemetry disabled. Ordinary checks do not require dbt and
skip that external integration test; both separate backend runs executed it.

Additional regressions covered isolated artifact directories, missing files,
mismatched invocation IDs, malformed scalar result fields, failed nodes despite
exit code 0, arguments passed without a shell, overwrite protection, dm keys
and unchanged cache/release semantics through `dl_ingest()`.

The local starter used dbt-duckdb profiles. Automatic v2 catalog generation,
dbt v2/Fusion, production S3/PostgreSQL, concurrent writers, Windows/macOS and
sustained load testing were not verified.

## Historical record: 0.2.0

Version 0.2.0 passed 26 test cases with 126 expectations on each backend.
These historical results do not establish the behavior of later versions.
Local session files and raw logs are not part of the public source tree.

## Historical record: 0.1.0

Check date: 18 September 2026. Ubuntu 24.04, R 4.3.3.

| Check | Result |
|---|---|
| Full suite on local DuckDB plus an additional DuckLake test | 21 tests, 97 passing expectations |
| Full suite with DuckLake as the default backend | 21 tests, 97 passing expectations |
| Failed, skipped or warning tests | 0 in each category |
| `R CMD build` | Successful |
| `R CMD check --no-manual --no-build-vignettes` with DuckLake enabled | 0 errors, 0 warnings, 0 notes |
| Included end-to-end example on DuckLake | Successful |
| Shiny reactivity, search, definitions, quality and graph output | Automatically checked |
| Shiny overview and lineage graph in Chromium | Rendered with no Shiny output errors; screenshots inspected |
| S3 landing against a local HTTP test server using paws.storage | Original bytes preserved; conditional PUT retries did not overwrite them |

All test data were synthetic. Raw logs and screenshots were kept outside the
public source tree.

### Failure cases covered

* Valid, invalid, missing and corrected deliveries.
* Failed gates leaving published data unchanged.
* Retries without duplicate publication or reactivation of old releases.
* Historical reads after corrections and reconnection.
* Missing columns, duplicates, failed/skipped rules and empty candidates.
* Tolerance boundaries and explicitly non-blocking warnings.
* Changed definitions reusing the same version.
* Notification deduplication, recurrence after recovery and transport failure.
* Data age without a new job and stable paths after a working-directory change.
* Partition corrections retaining other periods.
* Failure before transaction commit rolling back release and success markers.
* Products with pinned input versions.
* Unapproved metrics, forbidden dimensions and multiple dates for stock metrics.
* Metric values changed before report publication.
* pointblank checks including inactive steps.
* dm primary/foreign keys including orphaned references.
* Explicit YAML export and invalid identifiers.

### Main dependency versions

| Package | Version |
|---|---|
| duckdb | 1.5.5 |
| DBI | 1.2.2 |
| dplyr | 1.2.1 |
| dbplyr | 2.4.0 |
| pointblank | 0.12.4 |
| dm | 1.1.2 |
| shiny | 1.8.0 |
| bslib | 0.12.0 |
| paws.storage | 0.10.0 |

This records a tested combination rather than compatibility with every past or
future dependency version. Lock dependencies in each operating project.

## Operational verification still required

* A production S3 endpoint with authentication and conditional PutObject support.
  The local HTTP test server does not establish those endpoint guarantees.
* A PostgreSQL catalog, its backup/restore process and catalog migration.
* Deployment of the operating templates to Workbench, Connect or a scheduled
  GitHub workflow. Package CI and documentation deployment are separate.
* Quarto rendering on Connect and production notification transport.
* A running commons/data-dict project. YAML export is a limited interface.
* Large production datasets, concurrent writers, sustained load and Windows/macOS.

The tests establish the recorded behavior in their environments. The package
reports `multi_writer = FALSE` and does not automatically remove historical data.
