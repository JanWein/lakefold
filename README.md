# tidyweave

**Turn repeated data work into a small, reusable R workflow.**

You already know how to read a file, clean a table and calculate a result.
tidyweave connects those steps with checks, publication and execution evidence.
The next delivery follows the same instructions. A failed check is visible.
When you choose a lake target, a correction creates a new version while earlier
reports can keep reading the exact data they used.

## Start with a table

```r
# Development version; R >= 4.2
install.packages("remotes")
remotes::install_github("JanWein/tidyweave")
```

```r
library(tidyweave)

orders <- product("orders") |>
  add_source(data.frame(id = 1:3, amount = c(25, 75, 50)))

orders |> run() |> collect()
```

A **product** is a name and the instructions for producing a table. `run()`
executes those instructions; `collect()` returns an ordinary tibble. This example
needs no database, catalog, owner field or manual version number.

## Add one capability at a time

```r
orders <- orders |>
  add_transform(function(data) transform(data, amount = round(amount, 2))) |>
  add_contract(c(id = "integer", amount = "numeric")) |>
  add_quality(~ amount >= 0)

result <- run(orders)
quality(result)
```

Functions remain ordinary R functions. Contracts describe the expected table.
Quality rules decide whether its contents are acceptable. Checks do not silently
remove bad rows. Printing a product shows its components; `explain(orders)`
explains the plan. `validate(orders)` checks configuration without fetching data,
and `run()` does this automatically.

Multiple sources use names. Products can also be sources of other products.
The same composition works with local tables or supported lazy DBI/Arrow inputs.
Use `collect()` where an R-only algorithm needs data in memory.

## Save data when you need to

```r
# Optional, for a local lake with release history:
install.packages("duckdb")
published <- orders |> publish(to = "reporting-lake")
collect(published)
```

`run()` without a target keeps the result in memory. `publish()` supplies a
local lake target when none is configured. Publishing means writing checked
data to the selected destination; **it does not make data public on the internet**.
A lake keeps immutable releases and checks the complete candidate before making
it current. Other targets have their own persistence guarantees.

| Need | Optional addition |
|---|---|
| Query an existing database | `source_database(con, table = "orders")` |
| Read Parquet or an API | `source_parquet(...)`, `source_api(...)` |
| Write a database table, file or pin | `target_database(...)`, `target_parquet(...)`, `target_pins(...)` |
| Use specialist checks or SQL builds | pointblank and dbt adapters |
| Keep local run history | `run(orders, evidence = "runs")` |
| Send lineage or catalog metadata | `catalog_openlineage(...)`, `catalog_openmetadata(...)` |
| Manage a dependency graph or deployment | `as_targets(...)`, `init_project(...)` |

## Grow into a layered data stack

When several reports reuse the same deliveries, separate receiving data from
preparing it and approving it for consumers. The optional lake/dbt workflow adds
four explicit layers: **raw**, **staging**, **core** and **marts**.

```r
# After configuring a lake and providing orders.csv (see the guide below):
accepted <- ingest(config, "orders.csv", name = "orders",
  quality = ~ amount >= 0)

project <- dbt_init("analytics", config, sources = list(orders = accepted))
built <- dbt_build(project)
approved <- dbt_publish(config, built, "customer_revenue")

collect(approved)
```

`ingest()` checks a delivery before writing RAW and retains receipt evidence when
it rejects one. dbt then builds `stg_orders`, `core_orders` and `customer_revenue`
from the accepted release. `dbt_publish()` takes a checked, immutable snapshot for
consumers. A dbt data-test failure can leave earlier model writes in place; it
does not change an already published release. Without an explicit contract,
publication infers structure and does not invent business rules.

The [step-by-step layered guide](https://janwein.github.io/tidyweave/articles/layered-data-stack.html)
starts with real R data, explains each layer and shows optional pointblank,
DuckLake, OpenMetadata and report consumption. Shiny and Quarto use ordinary R
tables. Power BI can consume an approved database or Parquet export through its
existing connectors; deployment and refresh remain external responsibilities.

## Learn by building

1. [Why use it?](https://janwein.github.io/tidyweave/articles/why-tidyweave.html)
   A concrete explanation of the problem and benefits.
2. [Compose a product](https://janwein.github.io/tidyweave/articles/composing-products.html)
   One table, checks, several inputs and optional storage.
3. [Monthly reporting](https://janwein.github.io/tidyweave/articles/getting-started.html)
   Accept a correction, reject a duplicate and reproduce an issued report.
4. [A layered data stack](https://janwein.github.io/tidyweave/articles/layered-data-stack.html)
   Receive checked RAW data, build SQL layers and approve outputs for consumers.
5. [Architecture](https://janwein.github.io/tidyweave/articles/workflow-design.html)
   How a simple API supports interchangeable components.
6. [Write an adapter](https://janwein.github.io/tidyweave/articles/extending-tidyweave.html)
   A complete source, target and quality extension.

[Function reference](https://janwein.github.io/tidyweave/reference/index.html) ·
[Architecture review](https://github.com/JanWein/tidyweave/blob/main/docs/REFACTOR_REVIEW.md) ·
[Modern stack comparison](https://github.com/JanWein/tidyweave/blob/main/docs/MODERN_DATA_STACK.md) ·
[Validation record](https://github.com/JanWein/tidyweave/blob/main/docs/VALIDATION.md)

## Why this architecture

The public API uses readable verbs, pipes and familiar R objects. Internally,
normalization, specifications, preflight and S3 adapters separate the requested
work from its implementation. Structural ideas from tidymodels support this
modularity; users do not need machine-learning concepts or another object system.

![A small product definition is normalized and validated, then executed with interchangeable components.](vignettes/figures/composition-architecture.svg)

DBI, Arrow, pointblank, dbt and other specialist tools keep their own jobs.
tidyweave supplies composition and evidence. It does not provide a scheduler,
streaming engine, enterprise identity system or distributed transaction manager.
Lake and local evidence writes require one coordinated writer. Lazy execution
still depends on the operations supported by the selected backend.

**0.9.0 is a development version, not a stable release candidate.** Public APIs
may change without compatibility aliases. The package was previously named
lakefold. See [CONTRIBUTING.md](CONTRIBUTING.md) for the English documentation,
Posit skills, testing and package-development workflow. MIT licensed.
