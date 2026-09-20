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

orders <- product("orders", data.frame(id = 1:3, amount = c(25, 75, 50)))

orders |> run() |> collect()
```

A **product** is a name and the instructions for producing a table. `run()`
executes those instructions; `collect()` returns an ordinary tibble. This example
needs no database, catalog, owner field or manual version number.

## Add one capability at a time

```r
orders <- orders |>
  dplyr::mutate(amount = round(amount, 2)) |>
  add_contract(c(id = "integer", amount = "numeric")) |>
  add_quality(~ amount >= 0)

result <- run(orders)
quality(result)
```

The dplyr call is deferred until execution and uses ordinary dplyr semantics.
`add_transform()` still accepts ordinary R functions. Contracts describe the expected table.
Quality rules decide whether its contents are acceptable. Checks do not silently
remove bad rows. Printing a product shows its components; `explain(orders)`
explains the plan. `validate(orders)` checks configuration without fetching data,
and `run()` does this automatically.

Use `add_lookup(customers, by = dplyr::join_by(customer_id))` for a checked
many-to-one enrichment. Parent keys must be unique and non-missing; unmatched
children fail by default. `engine = "dm"` selects optional dm validation.
`add_quality(~ amount >= 0, engine = "pointblank")` changes the quality engine
without changing the predicate. Advanced agents and arbitrary R functions remain
available when a simple predicate is insufficient.

Products and successful results can be inputs to another product. Lake results
pin immutable releases. Other results reuse their retained submitted table or
lazy query, with the original backend's mutability; a DBI append result reuses
the submitted batch. Product definitions execute their instructions. `collect()`
is explicit when an R-only algorithm needs data in memory. Lake publication
materializes data for archival and validation.

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
config <- lake_config(path = "reporting-lake", backend = "duckdb",
  layers = c("raw", "staging", "core", "marts"))

accepted <- product("orders", "orders.csv") |>
  add_quality(~ amount >= 0) |>
  ingest(to = config)

# With an existing SQL project whose models use source('inputs', 'orders'):
approved <- dbt_project("analytics", lake = config,
    sources = list(orders = accepted)) |>
  run() |>
  publish("customer_revenue")

collect(approved)
```

`ingest()` checks the received data before RAW and retains receipt evidence when
it rejects a delivery. The managed dbt project supplies its connection and exact
source references. SQL models and dbt tests remain ordinary project files;
`dbt_init()` provides an optional small starter. `publish()` takes a checked,
immutable snapshot for consumers. Earlier dbt model writes are not rolled back
when a later test fails. Without a contract, publication infers structure and
does not invent business requirements.

The [step-by-step layered guide](https://janwein.github.io/tidyweave/articles/layered-data-stack.html)
starts with real R data, explains each layer and shows optional pointblank,
DuckLake, OpenMetadata and report consumption. Shiny and Quarto use ordinary R
tables. Power BI can consume an approved database or Parquet export through its
existing connectors; deployment and refresh remain external responsibilities.

For a complete worked example with several tables, the
[relational insurance walkthrough](https://janwein.github.io/tidyweave/articles/relational-insurance.html)
checks three deliveries, uses dm to enrich two independently contracted data
products, builds dbt reporting models and preserves an issued report after a
correction. It explains the meaning of each row and how to avoid counting
premium due more than once when a policy has several payments.

## Learn by building

1. [Why use it?](https://janwein.github.io/tidyweave/articles/why-tidyweave.html)
   A concrete explanation of the problem and benefits.
2. [Compose a product](https://janwein.github.io/tidyweave/articles/composing-products.html)
   One table, checks, several inputs and optional storage.
3. [Monthly reporting](https://janwein.github.io/tidyweave/articles/getting-started.html)
   Accept a correction, reject a duplicate and reproduce an issued report.
4. [A layered data stack](https://janwein.github.io/tidyweave/articles/layered-data-stack.html)
   Receive checked RAW data, build SQL layers and approve outputs for consumers.
5. [Relational insurance reporting](https://janwein.github.io/tidyweave/articles/relational-insurance.html)
   Multiple inputs, real dm enrichment, reusable products, dbt and governed measures.
6. [Architecture](https://janwein.github.io/tidyweave/articles/workflow-design.html)
   How a simple API supports interchangeable components.
7. [Write an adapter](https://janwein.github.io/tidyweave/articles/extending-tidyweave.html)
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

**0.10.0 is a development version, not a stable release candidate.** Public APIs
may change without compatibility aliases. The package was previously named
lakefold. See [CONTRIBUTING.md](CONTRIBUTING.md) for the English documentation,
Posit skills, testing and package-development workflow. MIT licensed.
