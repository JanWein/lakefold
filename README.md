# lakefold

**Turn data preparation and checks into a workflow you can reuse.**

Start with an ordinary R table. Add a transformation or quality rule when you
need one. Run the result in memory, or publish checked versions that reports can
read again later. Sources, storage and specialist tools can change without
rewriting the product's higher-level workflow.

## Start in a minute

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
```

```r
library(lakefold)

orders <- dl_product("orders") |>
  dl_add_source(data.frame(id = 1:3, amount = c(25, 75, 50))) |>
  dl_add_quality(~ amount >= 0)

result <- dl_run(orders)
dl_collect(result)
# A tibble with the three checked orders.
```

That is a complete in-memory workflow. No database, catalog, manual version or
business metadata is required. `dl_run()` returns the data and execution
evidence; `dl_collect()` gives you an ordinary tibble.

[Follow the illustrated step-by-step introduction](https://janwein.github.io/lakefold/articles/composing-products.html)
for the purpose, benefits and each addition to this example.

## Add only what you need

```r
clean_orders <- function(data) {
  transform(data, amount = round(amount, 2))
}

orders <- orders |>
  dl_add_transform(clean_orders) |>
  dl_add_contract(c(id = "integer", amount = "numeric"))

orders                 # A concise overview
dl_validate(orders)    # Check the definition without fetching data
dl_plan(orders)        # See the execution order
dl_quality(dl_run(orders))
```

Sources accept tables, paths and functions. CSV, TSV and RDS work directly;
Excel uses optional readxl. A DBI source accepts an existing connection or a
connection factory. R functions need no special transformation class.

| Need | Optional addition |
|---|---|
| Reuse preparation | `dl_add_transform(clean_orders)` |
| Declare types, keys or required fields | `dl_add_contract(contract)` |
| Check a simple business rule | `dl_add_quality(~ amount >= 0)` |
| Use advanced quality assertions | `dl_add_quality(dl_pointblank(...))` |
| Query a DBI database | `dl_add_source(dl_source_database(con, table = "orders"))` |
| Transform with SQL | `dl_add_transform(dl_sql("SELECT * FROM data"))` |
| Select storage | `dl_add_target(target)` |
| Deliver run metadata | `dl_add_catalog(function(metadata) ...)` |
| Add another implementation | Register ordinary S3 adapter methods |

Contracts and quality checks are independently usable:
`dl_validate(data, contract)` returns a quality tibble. Products compose those
checks with acquisition, preparation and publication.

## Publish when history matters

Install optional DuckDB >= 1.5.5, then select a folder:

```r
install.packages("duckdb")
published <- orders |> dl_publish(to = "reporting-lake")
dl_collect(published)
```

A lake target archives the received input, checks the proposed table and makes
a new immutable release available only when its checks pass. Corrections create
new releases; old releases remain readable. A failed check leaves the latest
successful release in place. Publishing here means making data available in the
chosen storage, not making it public on the internet.

The default target for `dl_publish()` is the `lakefold` folder. `dl_run()` stays
in memory until a target is added. To submit an already prepared table directly:

```r
data.frame(id = 1:2) |> dl_publish("identifiers", to = "reporting-lake")
```

The existing `dl_open()`, `dl_write()` and `dl_read()` shortcuts, explicit lazy
pipelines, derived products, metrics and report manifests remain supported.

## Why this architecture

The external API follows tidyverse principles: clear verbs, pipes, ordinary R
objects and progressive configuration. Internally, normalization, specifications,
validation, planning and adapters keep components interchangeable. This uses
structural ideas from tidymodels without introducing machine-learning terminology
or requiring specification objects for ordinary functions.

![Simple product verbs become a validated plan executed through native R, governed lake storage or a custom adapter.](vignettes/figures/composition-architecture.svg)

DuckDB/DuckLake handle governed storage, DBI handles connectivity, pointblank
handles advanced checks, and dbt owns its SQL build graph. Integrations stay
optional. An extension package can add a source, transformation, quality engine,
target or catalog without changing lakefold's core.

## Learn more

| Question | Guide |
|---|---|
| Why use it, and how do I build a workflow? | [Compose a product step by step](https://janwein.github.io/lakefold/articles/composing-products.html) |
| How do I implement another backend? | [S3 extension guide](https://janwein.github.io/lakefold/articles/extending-lakefold.html) |
| How do I keep monthly corrections and old reports? | [Monthly reporting walkthrough](https://janwein.github.io/lakefold/articles/getting-started.html) |
| How does pointblank fit? | [Quality gates](https://janwein.github.io/lakefold/articles/quality-gates.html) |
| How does dbt fit? | [dbt workflows](https://janwein.github.io/lakefold/articles/dbt-workflows.html) |
| How do I use lazy pipelines? | [Workflow design](https://janwein.github.io/lakefold/articles/workflow-design.html) |
| What changed architecturally? | [Review](docs/REFACTOR_REVIEW.md) and [architecture](docs/ARCHITECTURE.md) |
| How do I upgrade? | [Migration](docs/MIGRATION.md) |
| What was tested? | [Validation record](docs/VALIDATION.md) |
| What arguments can I use? | [Function reference](https://janwein.github.io/lakefold/reference/index.html) |

Version **0.7.0** supports R >= 4.2. The composed product path processes ordinary
R tables in memory. Existing lazy pipelines, derived products and dbt serve
larger workloads. Lake registry writes require one coordinated writer. Custom
targets provide only their documented persistence and atomicity guarantees.
Production S3/PostgreSQL deployments need verification in their own environment.

## Development

Follow [CONTRIBUTING.md](CONTRIBUTING.md). Development uses the Posit
[R package development and testing skills](https://github.com/posit-dev/skills)
and [R Packages documentation guidance](https://r-pkgs.org/man.html): roxygen2
function help, executable English vignettes, meaningful tests and full package
checks. The package was previously named dataloom; existing `dl_*` names remain
supported. MIT licensed.
