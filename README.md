# lakefold

**Complex data workflows, composed from simple R building blocks.**

lakefold is a modular R framework for turning incoming data into validated,
versioned data products and reproducible metrics. Start with a single ingestion
call, then compose explicit steps as your workflow grows. Sources, contracts,
pipelines, products and metrics share a small set of concepts: define, inspect,
execute and examine the result.

The framework combines DuckDB/DuckLake, dplyr, optional pointblank checks, dbt
builds and dm models. Ordinary R functions, tibbles and lazy tables remain part
of the interface. Each component has a clear responsibility, and you can use the
parts your workflow needs.

> Development version 0.4.0. The registry requires one coordinated writer.
> Local workflows have automated test coverage. See the
> [validation record](https://github.com/JanWein/lakefold/blob/main/docs/VALIDATION.md)
> for tested environments and the
> [feature overview](https://github.com/JanWein/lakefold/blob/main/docs/FEATURES.md)
> for current boundaries.

## Installation

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)
library(lakefold)
```

R >= 4.2 and DuckDB >= 1.5.5 are required. Building vignettes requires Pandoc,
which is normally available with RStudio. Use `build_vignettes = FALSE` if
Pandoc is unavailable. dbt workflows additionally need
`install.packages(c("processx", "yaml", "dm"))` and a separate dbt installation.
The R ingestion workflow works without dbt.

## Start with one ingestion call

This complete example writes to a temporary directory and runs without the
DuckLake extension.

```r
library(lakefold)
root <- tempfile("lakefold-")
config <- dl_config(
  dl_catalog_duckdb(file.path(root, "lake.duckdb")),
  dl_storage_local(file.path(root, "data")),
  landing = file.path(root, "landing"), backend = "duckdb"
)
lake <- dl_connect(config)

path <- file.path(root, "orders.csv")
utils::write.csv(data.frame(order_id = 1:3, amount = c(25, 75, 50)),
  path, row.names = FALSE)
source <- dl_source("orders.file", path, reader = utils::read.csv)
contract <- dl_contract(
  "orders.contract", "1.0.0", "Analytics", "Order amounts", "One order",
  c(order_id = "integer", amount = "numeric"), key = "order_id"
)

release <- dl_ingest(lake, source, contract, "orders", code_version = "v1")
dl_tbl(lake, "orders", release$release_id) |> dplyr::collect()
dl_disconnect(lake)
unlink(root, recursive = TRUE)
```

Invalid deliveries are recorded and block publication. The previous valid
release remains available. Identical inputs and definitions can reuse an
existing release.

## Grow into an explicit workflow

Use `dl_ingest()` for a compact file workflow or `dl_ingest_data()` for a data
frame already in R. When you need more control, compose `dl_pipeline()` with
landing, extraction, optional input checks, named transformations, validation and
publication steps. `dl_plan()` exposes the declared structure before execution.

`dl_execute()` is the common execution entry point for pipelines, products,
metrics and dbt projects. `dl_status()`, `dl_quality()`, `dl_releases()` and
`dl_lineage()` make the results inspectable. The
[workflow guide](https://janwein.github.io/lakefold/articles/workflow-design.html)
shows how to combine these building blocks.

The design goal is a small, consistent interface that accommodates complex
workflows through composition. Modules retain explicit inputs, outputs and
lifecycle rules as a workflow expands. See the
[design review](https://janwein.github.io/lakefold/articles/design-review.html)
for the framework's principles and extension boundaries.

## Run dbt from R

```r
# For an existing, configured dbt project directory:
project <- dl_dbt_project("analytics", profiles_dir = "analytics")
result <- project |> dl_execute(select = "+customer_revenue")
dl_dbt_status(result)
dl_dbt_lineage(result)
```

`dl_dbt_init(path, config)` can create a local starter project with synthetic
data and tests. The [dbt guide](https://janwein.github.io/lakefold/articles/dbt-workflows.html)
covers installation, DuckLake connections, diagnostics and subsequent use of dm.
Close R connections to the local catalog before invoking dbt, then reopen them.
Each invocation has its own artifacts, exit code and structured results.

## Component responsibilities

| Task | Interface | Behavior |
|---|---|---|
| Define specifications | `dl_config()`, `dl_pipeline()`, `dl_dbt_project()` | Construction does not start data processing |
| Ingest data | `dl_ingest()`, `dl_ingest_data()`, pipeline steps | Preserve an input snapshot, check its contract and publish a release |
| Build and test SQL models | `dl_dbt_build()`, `dl_dbt_test()` | dbt owns its dependency graph and materializations |
| Transform in R | `dl_step_transform()`, `dl_product()` | Use ordinary R functions and lazy operations where supported |
| Work with related tables | `dl_model()`, `dl_dbt_model()` | Use native dm objects with explicitly declared keys |
| Calculate metrics and record reports | `dl_metric()`, `dl_measure()`, `dl_report_release()` | Record versioned definitions and input references |
| Inspect metadata | `dl_registry()`, `dl_catalog()` | Query the registry or use the read-only Shiny catalog |

## Quality gates with pointblank

Install the optional integration with `install.packages("pointblank")`.
pointblank checks values and segments, dbt builds and tests SQL models, and dm
represents explicitly declared relationships.

```r
rule <- dl_pointblank("amounts", function(data) {
  pointblank::create_agent(data,
    actions = pointblank::action_levels(warn_at = 0.005, stop_at = 0.05)) |>
    pointblank::col_vals_gte("amount", 0, segments = pointblank::vars(entity))
}, policy = "agent")
```

Pass `input_contract` to `dl_ingest()` or `dl_ingest_data()` to validate the
delivery before writing Raw. Use `dl_step_precheck()` in an explicit pipeline.
Landing evidence is retained, and the final candidate check remains mandatory.
Evaluation errors, skipped checks and empty plans block publication.

| Building block | Purpose |
|---|---|
| `dl_contract_from()`, `dl_contract_confirm()`, `dl_contract_diff()` | Draft types, review the contract and compare changes |
| `dl_status()`, `dl_quality()`, `dl_releases()`, `dl_lineage()` | Inspect outcomes and provenance without querying registry internals |
| `dl_quality_report()`, `dl_pointblank_report()`, `dl_expect_quality()` | Export HTML/JSON or native reports and use the same gate in testthat |
| `dl_dbt_publish()` | Copy a current dbt relation, validate it and publish an immutable release |
| `dl_check_delivery()` | Detect overdue business dates even when no import has started |
| `dl_cleanup()` | Preview and remove expired unpublished tables from failed runs |

The [executable quality guide](https://janwein.github.io/lakefold/articles/quality-gates.html)
walks through thresholds, segmentation, blocked deliveries and reports.

## Documentation

| Goal | Start here |
|---|---|
| Create your first data product | [Getting started](https://janwein.github.io/lakefold/articles/getting-started.html) |
| Connect dbt, DuckLake and dm | [dbt workflows](https://janwein.github.io/lakefold/articles/dbt-workflows.html) |
| Compose and extend a pipeline | [Workflow design](https://janwein.github.io/lakefold/articles/workflow-design.html) |
| Handle quality failures and historical data | [Quality and history](https://janwein.github.io/lakefold/articles/quality-history.html) |
| Reproduce metrics and report values | [Products and metrics](https://janwein.github.io/lakefold/articles/products-metrics.html) |
| Use pointblank quality gates | [Quality gates](https://janwein.github.io/lakefold/articles/quality-gates.html) |
| Operate the package | [Operations](https://github.com/JanWein/lakefold/blob/main/docs/OPERATIONS.md) |
| Understand the design and scope | [Design review](https://janwein.github.io/lakefold/articles/design-review.html) |
| Inspect test evidence | [Validation record](https://github.com/JanWein/lakefold/blob/main/docs/VALIDATION.md) |
| Upgrade from dataloom or an earlier version | [Migration](https://github.com/JanWein/lakefold/blob/main/docs/MIGRATION.md) |

In R, use `help(package = "lakefold")`, `?dl_ingest`, `?dl_dbt_build` and
`vignette(package = "lakefold")`. Function help is generated from roxygen2
comments. GitHub Actions checks the package and publishes the pkgdown website.
All package documentation is maintained in English.

## Development

The [contribution guide](CONTRIBUTING.md) covers formatting, tests and full
package checks. Development follows the Posit
[`r-package-development` and `testing-r-packages` skills](https://github.com/posit-dev/skills)
and the [R Packages documentation guidelines](https://r-pkgs.org/man.html).

The package was previously named **dataloom**. Existing `dl_*` function names
remain available. MIT licensed.
