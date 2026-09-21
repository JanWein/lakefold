# tidyweave

**Define your data work once. Check a delivery, publish it and reuse the same
instructions for the next one.**

tidyweave brings ordinary R tables, dplyr transformations, quality checks and
versioned results into one workflow. Start with a table. Add storage when you
need history. Earlier published results and issued reports keep their original
inputs when a correction arrives.

## Start with a table

```r
# Development version; R >= 4.2
install.packages("remotes")
remotes::install_github("JanWein/tidyweave")
```

```r
library(tidyweave)

orders <- product("orders", data.frame(id = 1:3, amount = c(25, 75, 50))) |>
  dplyr::mutate(amount = round(amount, 2)) |>
  add_quality(~ amount >= 0)

result <- orders |> trial()
collect(result)
```

A **product** holds the instructions. `trial()` tries them without configured writers; `collect()` returns
an ordinary tibble. The example needs no database, owner field or version number.
Use familiar dplyr expressions to explore the collected table. Add an explicit
contract when you know the required types, business key and meaning of a row.

## Understand a failed delivery

```r
bad_delivery <- data.frame(id = 1:3, amount = c(-25, 75, 50))
failed <- orders |> trial(data = bad_delivery)
status(failed)
quality_report(failed)
quality_rows(failed)
```

Checks reject unacceptable data; they do not silently drop bad rows. The
result carries its diagnostic evidence. `quality_report()` returns a table when
no output path is supplied. `quality()` gives the underlying checks, and
`lineage()` explains the inputs.

## Publish, then accept the next delivery

For an actual local **DuckLake**, start with a new folder:

```r
lake <- open_lake("my-ducklake", backend = "ducklake",
  layers = c("raw", "staging", "core", "marts"))
close_lake(lake)
lake <- open_lake("my-ducklake") # Backend and layers are remembered
close_lake(lake)
```

This needs optional `duckdb` and its DuckLake extension. Follow
[Create a DuckLake](https://janwein.github.io/tidyweave/articles/create-ducklake.html)
to save data, reopen the folder and publish the next delivery. Omitting the
backend for a new folder selects ordinary DuckDB, as in the simpler example below.

```r
# Optional dependency for a local lake with release history:
install.packages("duckdb")
first <- orders |> publish(to = "reporting-lake")

corrected <- data.frame(id = 1:3, amount = c(30, 75, 50))
second <- orders |> publish(data = corrected, to = "reporting-lake")
collect(first)  # Original values remain available
collect(second)
```

`trial()` disables configured targets and catalogs throughout the product graph.
`run()` executes the configured workflow, including any configured targets. `publish()` writes checked data
to the chosen destination, not to the public internet. The local lake keeps
immutable releases and checks the complete candidate before making it current.
These deliveries replace the complete table. Complete-month replacement is an
explicit storage choice, not something inferred from a date column.

For repeated work, keep optional engine and destination defaults in one ordinary
value: `execution_config(to = "reporting-lake")`. Pass it as the product's
`execution` argument. Step-specific choices remain explicit; defaults are not
global settings. In workflows with several inputs, supply a named `sources` list
at execution. Stable source names and nested product IDs identify what changed.

Compare these publications with `compare(first, second, key = "id")`. If a
contract already declares the key, `compare(first, second)` reuses it. No manual lake
connection or release-ID lookup is needed.

## Calculate and keep a report

```r
metrics <- metric_set("orders",
  total = sum(amount),
  count = dplyr::n(),
  code_version = "orders-v1", approved = TRUE)

values <- second |> measure(metrics = metrics)
collect(values)
values |> report_release("orders-report-v1", code_version = "report-v1")
report_read("reporting-lake", "orders-report-v1", values_only = TRUE)
```

Metric sets share their product, dimensions and time settings. For exploration,
omit approval and code version; saving an issued report requires explicitly
approved, versioned definitions. Approval records your decision, not an external
authorization process. Report readback retrieves saved values without recalculating.
`dimensions` lists permitted columns; `measure(by = "company")` chooses the
report grouping. `by = character()` explicitly requests an overall total.
An issued report stores values and their provenance; use your usual reporting
tools to render a document.

Use the same metrics on `trial(orders)` while exploring. Trial measurements cannot
be issued as reports; publish and recalculate when ready.

For a multi-step monthly process, define a `workflow()` of named functions once.
Function arguments declare dependencies, including receipt, product and dbt steps.
`run(flow, inputs = list(payments = corrected), previous = first_run)` reruns
affected branches and exposes step status. Keep report issuance explicit.

## Follow one guide, then add what you need

Start with [the everyday workflow](https://janwein.github.io/tidyweave/articles/everyday-workflows.html):
three named deliveries, one data error, a report and corrections to either the
main delivery or a reference table. Keep the same names throughout:

```r
# Given payment and contract tables:
payments <- product("payments", payment_data) |>
  add_lookup(contract_data, by = "policy_id", name = "contracts")
explain(payments)
trial(payments, sources = list(contracts = corrected_contract_data))
```

| When you need it | Guide |
|---|---|
| Several tables and checked lookups | [Compose products](https://janwein.github.io/tidyweave/articles/composing-products.html) |
| Checked receipt data and SQL layers | [A layered data stack](https://janwein.github.io/tidyweave/articles/layered-data-stack.html) |
| Full insurance workflow with dm, dbt and corrections | [Relational insurance reporting](https://janwein.github.io/tidyweave/articles/relational-insurance.html) |
| Existing databases, files and specialist packages | [Optional integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html) |
| Complete-month corrections and report history | [Monthly reporting](https://janwein.github.io/tidyweave/articles/getting-started.html) |
| Implement another backend | [Write an adapter](https://janwein.github.io/tidyweave/articles/extending-tidyweave.html) |

The public API uses pipes, readable verbs and familiar R objects. Internally,
specifications, validation and S3 adapters separate the requested work from its
implementation, inspired structurally by tidymodels. DBI, Arrow, pointblank, dm
and dbt retain their specialist jobs. Advanced receipt workflows use `ingest()`;
low-level lake operations remain available in the integration reference.

Lake and local evidence writes need one coordinated writer. Lake publication
materializes a full candidate; lazy transformations depend on backend support.
A dbt build and its final publication are separate steps, with no distributed
transaction across the workflow. Scheduling, identity management, BI deployment
and remote-storage verification remain outside the core package.

**0.12.0 is a development version.** APIs may change before the first stable
release candidate; stored releases and issued-report evidence retain their
integrity requirements.

[Function reference](https://janwein.github.io/tidyweave/reference/index.html) ·
[Validation record](https://github.com/JanWein/tidyweave/blob/main/docs/VALIDATION.md) ·
[Contributing](CONTRIBUTING.md). MIT licensed.
