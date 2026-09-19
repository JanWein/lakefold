# lakefold

**Open. Write. Read. Add complexity when you need it.**

lakefold is a modular R framework for turning incoming data into validated,
versioned data products and reproducible metrics. Start with three calls and sensible local defaults, then compose explicit
steps as your workflow grows. Sources, contracts,
pipelines, products and metrics share a small set of concepts: define, inspect,
execute and examine the result.

The framework combines DuckDB/DuckLake, dplyr, optional pointblank checks, dbt
builds and dm models. Ordinary R functions, tibbles and lazy tables remain part
of the interface. Each component has a clear responsibility, and you can use the
parts your workflow needs.

> Development version 0.5.0. The registry requires one coordinated writer.
> Local workflows have automated test coverage. See the
> [validation record](https://github.com/JanWein/lakefold/blob/main/docs/VALIDATION.md)
> for tested environments and the
> [feature overview](https://github.com/JanWein/lakefold/blob/main/docs/FEATURES.md)
> for current boundaries.

## Installation

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
library(lakefold)
```

R >= 4.2 and DuckDB >= 1.5.5 are required. The basic workflow needs no dbt,
pointblank, DuckLake extension, credentials or external service. Read the
[online guides](https://janwein.github.io/lakefold/articles/getting-started.html),
or install with `build_vignettes = TRUE` for local guides (requires Pandoc).

## Start in three calls

```r
library(lakefold)
orders <- data.frame(id = 1:3, amount = c(25, 75, 50))

lake <- dl_open("my-lake")
dl_write(lake, orders)
dl_read(lake, "orders")

# Close when finished. dl_open("my-lake") reopens the same data later.
dl_close(lake)
```

`dl_write(lake, "orders.csv")` also works directly. CSV, TSV and RDS readers
are built in; a custom `reader` is optional. Data-frame expressions need a name,
for example `dl_write(lake, data.frame(id = 1:3), "orders")`.

The first successful write records column names and types. Later writes are
checked against that schema. Missing values are allowed; empty deliveries and
schema changes block publication and leave the last successful release intact.
The automatic schema makes no claims about business correctness.

## Add only what you need

| Need | Optional addition |
|---|---|
| Business rules or unique keys | `contract = dl_contract(...)` |
| Responsibility and meaning | `owner`, `description`, `grain`, column metadata |
| Detailed validation | pointblank rules in a contract |
| Nonstandard files | `reader = your_reader` |
| Freshness monitoring | A contract with `max_age_hours` |
| Large queries | `dl_read(lake, "orders", lazy = TRUE)` |
| Historical data | `release =` in `dl_read()` |
| DuckLake storage | `dl_open("another-lake", backend = "ducklake")` |
| Remote storage or custom layers | `dl_config()` and `dl_connect()` |
| Explicit transformation steps | `dl_pipeline()` |
| SQL models, related tables or metrics | dbt, dm and the corresponding modules |

A custom contract needs only its identifier and columns. Add a key when it
matters:

```r
contract <- dl_contract("orders.checked",
  columns = c(id = "integer", amount = "numeric"), key = "id")
# Pass contract = contract to dl_write() while the lake is open.
```

Explicit contracts require non-missing declared columns by default. Use
`required = character()` if missing values are allowed. Once an asset uses an
explicit contract, supply it on subsequent writes to keep its checks active.
Definition versions are automatic on the simple path. Custom readers and rules
run again by default; an explicit `code_version` enables deliberate cache reuse.

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
| Ingest data | `dl_write()`, `dl_ingest()`, `dl_ingest_data()`, pipeline steps | Preserve an input snapshot, check its contract and publish a release |
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

In R, use `help(package = "lakefold")`, `?dl_open`, `?dl_write` and
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
