# Operating lakefold 0.4.0

## dbt execution

Use one writing process per local catalog. Close R connections before invoking
dbt and reopen them afterward. Serialize tasks for the same catalog in the
scheduler. The registry does not implement distributed locks.

dbt logs and artifacts are stored per invocation under `.lakefold/runs/<id>`.
They can contain SQL, paths and database diagnostics. Keep them in the operating
project's controlled storage. The child process inherits its parent's
environment; credentials come from the dbt profile and environment variables.
Anonymous dbt telemetry is explicitly disabled for the child process.

On failure, inspect `result$success`, `dl_dbt_status(result)`, `result$stderr` and
`result$artifact_error`. `timeout` terminates a stalled child process. There is
no automatic retry, and a failed dbt invocation does not roll back every model
already built. After a successful selected build, open the corresponding
manifest nodes through `dl_dbt_model(tables = ...)`.

Operators manage artifact retention, secrets, backup and restore. S3/PostgreSQL
and dbt v2 require separately verified configuration. The starter generates local
dbt-duckdb profiles. Keep the R and Python DuckDB versions aligned.

## Configuration

[setup_s3.R](../inst/examples/setup_s3.R) uses these environment variables:

| Variable | Contents |
|---|---|
| `DATALOOM_S3_BUCKET` | Existing S3 bucket, required |
| `DATALOOM_S3_ENDPOINT` | Endpoint including `https://` and no path, required |
| `DATALOOM_S3_PREFIX` | Prefix, default `dataloom/dev` for compatibility |
| `AWS_DEFAULT_REGION` | Region, default `eu-central-1` |
| `AWS_ACCESS_KEY_ID` | Access key supplied at runtime |
| `AWS_SECRET_ACCESS_KEY` | Secret supplied at runtime |
| `AWS_SESSION_TOKEN` | Optional session token |
| `DUCKLAKE_PG_CONNECTION` | libpq connection string for a PostgreSQL catalog |

The `DATALOOM_S3_*` variables belong to the example script. Package constructors
receive configuration explicitly. Archiving originals on S3 requires
`paws.storage`; Parquet storage uses DuckDB httpfs. The S3 service must support
conditional PutObject to avoid overwriting originals. Verify this with a test
file in the target environment.

## PostgreSQL

Provision a database, configure TLS and runtime credentials, then use
`dl_catalog_postgres("DUCKLAKE_PG_CONNECTION")`. This constructor neither
provisions PostgreSQL nor migrates a local catalog. Back up database metadata
and S3 objects together, and exercise restoration. A metadata-only backup does
not contain the data files.

## Jobs and Posit Connect

The templates in `inst/templates/` separate definitions, an R job, a Quarto
report and a Shiny app. Use stable absolute file paths, configure environment
variables in the runtime and pass a Git commit as `DATALOOM_CODE_VERSION`.
Lock package dependencies in the operating project.

Use one writer for the shared lake. In a dedicated GitHub operating repository,
use the same `concurrency.group` and `cancel-in-progress: false` for all jobs
writing that lake. This only coordinates jobs within that repository. Connect
and GitHub Actions must not write the same lake concurrently. Package CI uses
isolated synthetic data and requires no production credentials. GitHub
concurrency is not a durable job queue; the scheduler must retain a traceable
run for each expected delivery.

## Failures and recovery

Monitor registry and job status. `dl_interrupted()` lists runs left in `running`
state. An identical retry can find already committed releases.
`dl_freshness()` checks data age; active monitoring requires an external
scheduler. Surface notification transport failures. After a Quarto render fails,
Connect may still display the last successful HTML. The registry records the
current run's outcome.

## Access and historical data

Contracts and quality gates do not enforce storage permissions. Direct SQL
clients can bypass framework rules. Catalog snapshots may include source paths,
descriptions and contacts. Share only snapshots approved for the intended
catalog audience. The public package repository contains no production
snapshots. Retain historical releases referenced by reports. General automatic
retention is not implemented.

## Delivery monitoring and cleanup

Call `dl_check_delivery()` from the existing scheduler. It checks an explicitly
expected business date and `due_at`, even without a preceding import attempt.
It compares the expected date with the latest published release; a recently
published older business date does not meet a new expectation. Notifications
are deduplicated after successful delivery, and transport failures remain
retryable. The catalog displays delivery status alongside data age and the
latest attempt.

`dl_cleanup(lake, older_than_days = 30)` returns a preview. With
`dry_run = FALSE`, eligible Raw/candidate tables from completed failed runs are
dropped in one transaction. Running jobs, published release tables, landing
files, quality evidence and reports are retained. Physical DuckLake file cleanup
and snapshot expiry remain separate operating tasks.

Quality reports and native pointblank reports can contain segment names and
business rules. Compact reports omit complete source rows. Save reports to the
operating project's intended location.

## Simple local workflows

`dl_open("my-lake")` stores the catalog, landing snapshots, data directory and
`lakefold.json` in one folder. Keep that configuration file with the catalog;
it records the backend. Reopen with the same call and close with `dl_close()`.
Back up the folder with all connections closed, using the backend's documented
backup requirements. Historical metadata can contain absolute file paths.

`dl_write()` checks the schema automatically. It sets no freshness deadline and
requires no owner or notification transport. Supply a contract when those
business requirements are known. After adopting an explicit contract, continue
supplying it on each write. The simple API shares the one-writer requirement.

For custom readers and rules, fresh evaluation is the default. Opt into cache
reuse with an explicit `code_version` covering dependencies and captured values.
Schema preparation for a first file happens before the normal run is created;
parsing failures retain the archived bytes but have no run-level quality report.
