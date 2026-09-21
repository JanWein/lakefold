# Operate a dataraft project

Start with a working product and add only the operating capabilities it needs.
The [optional integrations guide](https://janwein.github.io/dataraft/articles/optional-integrations.html)
contains executable local examples. This guide describes responsibilities at
execution, storage and service boundaries.

## Keep evidence and monitor failures

```r
result <- dr_run(orders_definition, evidence = "runs", stop_on_failure = FALSE)
dr_run_history("runs")
dr_incidents("runs")
dr_read_run("runs", result$run_id)
```

Without `evidence`, ordinary runs retain evidence in their R result. With it,
one JSON record per run contains status, times, input references, schema, quality
counts and metadata-delivery state. Source rows, open connections, request objects,
executable definitions and raw errors are excluded. Identifiers, paths and business
descriptions can still be operationally sensitive.

Use one coordinated writer for an evidence directory, including retry workers.
This local store is separate from publication: a process crash after a target
write but before evidence is saved requires reconciliation. It is not a distributed
transaction log. Keep evidence in storage that survives job restarts and deployment
updates. Targets cache hits reuse an earlier result and its timestamps; they are
not new product executions.

For local diagnosis use `result$error`, `result$warning_conditions`,
`dr_quality_errors()` or retained pointblank agents. Raw conditions may include values
or credentials; they stay in memory and are not the portable evidence payload.

## Publish metadata to external services

External catalogs are optional consumers of metadata. They do not replace the
lake's technical registry or control whether a completed data write occurred.

```r
lineage <- dr_catalog_openlineage(
  "https://lineage.example/api/v1/lineage",
  namespace = "analytics.production",
  request = function(request) {
    httr2::req_auth_bearer_token(request, Sys.getenv("LINEAGE_TOKEN"))
  }
)
metadata <- dr_catalog_openmetadata(
  "https://metadata.example",
  database_schema = "warehouse.analytics.public",
  source_tables = c(delivery = "warehouse.raw.public.orders"),
  request = function(request) {
    httr2::req_auth_bearer_token(request, Sys.getenv("METADATA_TOKEN"))
  }
)

orders_definition <- dr_product("orders") |>
  dr_add_source("orders.csv", name = "delivery") |>
  dr_add_catalog(lineage) |>
  dr_add_catalog(metadata)
dr_run(orders_definition, evidence = "runs")
```

Configure the actual service URL, TLS, credentials and permissions in your
runtime. Never put credentials in endpoint URLs. Request factories obtain fresh
authentication on every delivery. Package HTTP fixture tests verify requests and
responses locally; they do not establish compatibility with your deployed server.

OpenLineage sends **buffered START and COMPLETE/FAIL events after execution**,
using the recorded timestamps and a stable run UUID. It is historical lineage,
not live progress streaming. Failed or blocked runs report no output dataset.

OpenMetadata upserts a table only for successful runs. Its database service,
database and schema must already exist. `source_tables` maps `dr_add_source()` names
to existing fully qualified table names. Mapped sources receive table-level lineage;
unmapped sources and column-level lineage are not inferred. This adapter does not
provision infrastructure or implement the service's complete governance API.

See [OpenLineage](https://openlineage.io/docs/) and
[OpenMetadata](https://docs.open-metadata.org/) for service setup and supported
server behavior.

## Retry failed metadata delivery

Publication and metadata delivery are separate. A failed catalog request records
a warning and a pending delivery; it does not pretend that published data was
rolled back. Supply the destination adapters again, with fresh credentials:

```r
dr_retry_catalogs("runs", list(lineage, metadata))
dr_run_history("runs")
```

Only pending deliveries with matching destination IDs are attempted. A callback
registered with `dr_add_catalog(callback, name = "audit")` must be supplied as
`list(audit = callback)` when retrying. Callback code and authenticated requests
are not serialized into evidence.

Delivery is **at least once**. A server may accept a request before local
acknowledgement is saved. OpenLineage receivers should deduplicate by event/run
identity; a retry can repeat an accepted START event. OpenMetadata table upserts
and table-lineage edges are repeatable. Do not claim exactly-once delivery.

## Coordinate storage writers

A governed lake requires one coordinated writer. PostgreSQL catalogs now coordinate
package operations automatically with advisory locks; local file catalogs still
require one writer process. See the shared DuckLake guide for client requirements. Keep dbt and R writes to the same
local catalog sequential, closing R connections before the CLI opens it.
`dr_transform_dbt()` does this for its factory-owned connections. Other callers must
coordinate their own connections and jobs.

| Destination | Operating responsibility |
|---|---|
| DBI target | Verify driver transactions, isolation and transactional DDL; coordinate writers |
| Local Parquet file | Verify replacement/rename behavior on the actual filesystem |
| pins board | Configure authentication, retention and board-specific versioning |
| DuckDB/DuckLake lake | Coordinate a writer and back up metadata plus underlying data |
| S3/PostgreSQL lake deployment | Provision services, TLS and runtime secrets; verify conditional object writes and restore |

`dr_target_database(mode = "append")` checks the complete existing and incoming
candidate before writing. This collects the existing table. General remote
concurrency control, distributed locks and cross-system atomic commits remain
outside the package.

The environment-driven S3 example is [setup_s3.R](../inst/examples/setup_s3.R):

| Variable | Purpose |
|---|---|
| `DATARAFT_S3_BUCKET`, `DATARAFT_S3_ENDPOINT` | Existing bucket and endpoint |
| `DATARAFT_S3_PREFIX` | Object prefix; example default `dataraft/dev` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN` | Runtime authentication |
| `AWS_DEFAULT_REGION` | Region; example default `eu-central-1` |
| `DUCKLAKE_PG_CONNECTION` | PostgreSQL registry connection string when that backend is selected |

These example variables are not mandatory package configuration. Changing
`dr_registry_duckdb()` to `dr_registry_postgres()` connects to another registry. Back up registry metadata and data objects together,
and test restoration. A metadata-only backup cannot reconstruct the data files.

## Schedule a project

```r
dr_init_project("orders-project", targets = TRUE, renv = TRUE, connect = TRUE)
```

The generated project includes a runner, optional targets file, explicit renv
bootstrap script and Quarto job. Creation does not install packages, produce a
lockfile, deploy to Connect or configure a schedule. Follow its README to perform
those steps. Use `DATARAFT_EVIDENCE` for a persistent deployment evidence path.

Configure schedules, credentials and process isolation in your chosen platform.
For GitHub Actions, use a shared concurrency group for jobs writing the same lake;
this coordinates only that repository. Connect and other schedulers need the same
writer policy. A failed Quarto render can leave the previous successful HTML
visible; inspect job status and execution evidence as well as the report.

## Inspect and recover governed lake runs

`dr_interrupted(lake)` lists runs left in `running` state. Stop the original writer,
then preview recovery for explicit run IDs:

```r
dr_recover(lake, run_ids = selected_run_id, staging_assets = "orders")
# After reviewing the preview:
dr_recover(lake, run_ids = selected_run_id, staging_assets = "orders",
  dry_run = FALSE)
```

A known live process blocks recovery. For an owner whose liveness cannot be
verified, `writer_stopped = TRUE` is an explicit operator assertion after stopping
it externally. Recovery does not erase committed releases or landing evidence.
It is not a substitute for writer coordination.

`dr_cleanup(lake)` previews eligible unpublished tables from completed failed runs;
`dry_run = FALSE` performs that cleanup. Published releases, landing files, reports
and quality evidence remain. General history retention and DuckLake physical-file
expiry are separate operating tasks. Retain releases referenced by saved reports.

`dr_freshness()` and `dr_check_delivery()` provide checks for an external scheduler;
there is no background monitoring service. `dr_report_read()` reads saved report
values without rerunning formulas. Storage permissions remain essential: direct
SQL or filesystem clients can bypass framework quality gates.
