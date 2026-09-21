# tidyweave

**Turn repeated data deliveries into checked tables and reproducible reports.**

Define the preparation once, use it on the next delivery, and keep the data
behind an earlier report when a correction arrives. Start with ordinary R data
and dplyr. Add storage when you need history.

## Install

The development version needs R 4.2 or later:

```r
install.packages("remotes")
remotes::install_github("JanWein/tidyweave")
```

## Try your first product

A product is a reusable set of instructions for a named table.

```r
library(tidyweave)

delivery <- data.frame(id = 1:3, amount = c(25, 75, 50))
orders <- product("orders", delivery) |>
  dplyr::mutate(amount = round(amount, 2)) |>
  add_quality(~ amount >= 0)

result <- orders |> trial()
collect(result)
```

This returns the three checked rows, totalling **150**. `trial()` tries the
instructions without writing a publication; `collect()` returns an ordinary
tibble. No database or service is needed.

## Learn tidyweave

**[Get started: five short lessons](https://janwein.github.io/tidyweave/articles/get-started.html)**

Build a product, understand a failed check, save and correct a delivery, keep
report values, then bring the steps together in a monthly reporting example.
Each lesson explains its prerequisites and runs on its own.

Already know the basics? **[Find a guide for your task](https://janwein.github.io/tidyweave/articles/learn.html)**:
create a DuckLake, combine tables, add pointblank, use dbt, or connect existing storage.

Look up arguments in the **[function reference](https://janwein.github.io/tidyweave/reference/index.html)**.
If something fails, start with **[troubleshooting](https://janwein.github.io/tidyweave/articles/troubleshooting.html)**.

## Is it a fit?

tidyweave is useful when preparation repeats, bad deliveries must be rejected,
or earlier reported values must remain explainable. A one-off dplyr script may
be enough for a one-off analysis.

Local history requires optional DuckDB. Actual DuckLake is an explicit backend
choice, explained in [Create a DuckLake](https://janwein.github.io/tidyweave/articles/create-ducklake.html).
Lake writes require one coordinated writer. Other storage adapters have their
own guarantees; see [integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html).
Saved reports contain values and evidence, not rendered PDF or PowerPoint files.
Scheduling and access management stay with your existing tools.

The package is in development; APIs may change before the first stable release
candidate. [Why tidyweave?](https://janwein.github.io/tidyweave/articles/why-tidyweave.html)
explains the scope. [Contributing](CONTRIBUTING.md) covers development. MIT licensed.
