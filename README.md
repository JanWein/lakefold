# tidyweave

**Compose checked data products from reusable specifications and recipes.**

tidyweave separates what a table must satisfy, how it is prepared, and how the
work runs. Define each component once, reuse it for new deliveries, and retain
the data behind a report when corrections arrive.

## Installation

The development version requires R 4.2 or later:

```r
install.packages("remotes")
remotes::install_github("JanWein/tidyweave")
```

## Usage

```r
library(tidyweave)

orders <- tw_product("orders") |>
  tw_add_contract(tw_contract(
    columns = c(id = "integer", amount = "numeric"), key = "id"
  )) |>
  tw_add_quality(~ amount >= 0)

preparation <- tw_recipe() |>
  tw_step_mutate(amount = round(amount, 2))

flow <- tw_workflow() |>
  tw_add_product(orders) |>
  tw_add_recipe(preparation)

delivery <- data.frame(id = 1:3, amount = c(25, 75, 50))
result <- tw_trial(flow, data = delivery)
tw_collect(result)
```

The result is a tibble with three orders totalling **150**. Definitions do not
read or write data. `tw_trial()` executes preparation and checks with framework
writers disabled. Use `tw_publish(flow, data = delivery, to = "data/orders")`
to save checked output with the optional DuckDB dependency installed.

| Component | Defines | Main functions |
|---|---|---|
| Product specification | Identity, schema, keys and quality requirements | `tw_product()`, `tw_add_contract()`, `tw_add_quality()` |
| Recipe | Ordered preparation instructions | `tw_recipe()`, `tw_step_*()` |
| Workflow | Product, recipe, inputs and destination | `tw_workflow()`, `tw_add_product()`, `tw_add_recipe()` |
| Execution | A checked attempt and its evidence | `tw_trial()`, `tw_publish()`, `tw_collect()` |

The architecture follows [parsnip](https://parsnip.tidymodels.org/),
[recipes](https://recipes.tidymodels.org/) and
[workflows](https://workflows.tidymodels.org/). All tidyweave exports start with
`tw_`, so they can be used alongside those packages. Ordinary dplyr methods
remain available through dplyr. These recipes contain deferred instructions;
they have no fitted training state or `prep()` / `bake()` phase.

## Documentation

- [Get started](https://janwein.github.io/tidyweave/articles/get-started.html): one complete workflow, including a second delivery.
- [Product specifications](https://janwein.github.io/tidyweave/articles/first-product.html): state what acceptable output means.
- [Preparation recipes](https://janwein.github.io/tidyweave/articles/preparation-recipes.html): compose, reuse and inspect steps.
- [Workflows](https://janwein.github.io/tidyweave/articles/modular-workflows.html): assemble components, replace slots and execute.
- [Engines](https://janwein.github.io/tidyweave/articles/engines.html): select native, pointblank or dm implementations.
- [Articles](https://janwein.github.io/tidyweave/articles/learn.html) and [reference](https://janwein.github.io/tidyweave/reference/index.html): publication, reports, integrations and arguments.

Upgrading existing code? Read the [API migration guide](https://janwein.github.io/tidyweave/articles/api-migration.html).

## Scope

Start in memory. Optional adapters connect DBI, Arrow, pins, HTTP, dbt and
catalogs. Lake publication retains immutable releases; other targets keep their
documented storage semantics. Local lake writes require one coordinated writer.
DuckLake is an explicit backend choice. Saved reports contain values and
evidence; rendering, scheduling and access management remain with your tools.

The package is in development. Interfaces may change before the first stable
release candidate. See [Contributing](CONTRIBUTING.md). MIT licensed.
