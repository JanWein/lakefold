# lakefold

An R interface for governed file ingestion, DuckDB/DuckLake, dbt builds and lazy
relational analysis with dm. Formerly called dataloom; existing `dl_*` APIs remain.

```r
remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)
library(lakefold)
vignette("getting-started")
vignette("dbt-workflows")
```

Define specifications without executing them, inspect them, then call
`dl_execute()`. `dl_ingest()` provides concise contract-gated file ingestion.
`dl_dbt_init()` creates a local starter; `dl_dbt_project()` describes an existing
project. dbt build/test results and manifest edges are returned as tibbles.
`dl_dbt_model()` opens current dbt relations as a lazy `dm`; keys are explicit.

R >= 4.2, DuckDB >= 1.5.5. dbt is an external optional CLI. The starter targets
dbt-duckdb; v2 catalogs require an explicitly configured and verified project.
Close local R catalog connections before running dbt in a separate process.

Development release: a single registry writer is required. A dbt build is not
an atomic governed release. Automatic schema migrations, remote profile
provisioning, mixed R/dbt DAG scheduling and coordinated multi-writer execution
are not implemented. See the [design review](docs/DESIGN_REVIEW.md),
[validation record](docs/VALIDATION.md) and [migration guide](docs/MIGRATION.md).

Full function help ships in the installed package; the pkgdown site is built by
CI. MIT licensed. [German overview](README.md).
