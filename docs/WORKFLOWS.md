# Define, inspect and execute workflows

For the new product-first interface, start with the [composition guide](https://janwein.github.io/lakefold/articles/composing-products.html).
Lake examples require optional DuckDB >= 1.5.5; existing workflows remain supported.


## Connect at execution time

```r
library(lakefold)
config <- dl_config(
  catalog = dl_catalog_duckdb("metadata.ducklake"),
  storage = dl_storage_local("data"),
  landing = "landing"
)
config
```

These calls create no directories, load no extensions and open no connections.
Paths are resolved against the working directory. You can save a definition
with `saveRDS()`, but referenced files, packages and closure environments must
exist in the execution environment. The serialized object is not a portable,
language-independent exchange format.

`dl_setup(...)` combines configuration and connection for convenience.
`dl_connect(config)` opens an existing configuration.

## Use a common execution entry point

| Definition | Common API | Specific API |
|---|---|---|
| Pipeline | `pipeline |> dl_execute(lake)` | `dl_run(pipeline, lake)` |
| Product | `product |> dl_execute(lake)` | `dl_build(lake, product)` |
| Metric | `metric |> dl_execute(lake, at = date)` | `dl_measure(lake, metric, at = date)` |
| dbt project | `project |> dl_execute()` | `dl_dbt_build(project)` |

A pipeline carries its configuration, so `pipeline |> dl_execute()` is enough.
Products and metrics need a connection or `dl_config`. Supplied connections
remain open. Connections opened by `dl_execute()` are closed even on error.
For related operations, an explicit connection is usually more efficient.
dbt uses a separate process; close local catalog connections before invoking it.

```r
lake <- dl_connect(config)
# Inside a function: on.exit(dl_disconnect(lake), add = TRUE)
# ... execute operations ...
dl_disconnect(lake)
```

## Compose transformations

```r
pipeline <- dl_pipeline("finance.import", config, code_version = "git-sha") |>
  dl_step_land(source) |>
  dl_step_extract() |>
  dl_step_transform(
    function(data) dplyr::mutate(data, amount = amount * 1000),
    id = "amount_in_eur"
  ) |>
  dl_step_transform(
    function(data) dplyr::select(data, id, date, amount),
    id = "select_contract_columns"
  ) |>
  dl_step_validate(contract) |>
  dl_step_publish("finance.validated")

dl_plan(pipeline)
```

`source` and `contract` are previously defined objects; see the complete
[getting-started example](GETTING_STARTED.md). Steps may use ordinary R
functions and must return a data frame or lazy table. SQL-compatible lazy
operations remain in DuckDB. R-only functions must explicitly `collect()` and
have enough memory for the resulting data.

The reader processes the archived original. Transformations leave Raw unchanged
and produce the candidate input. For partition replacement, this input is
combined with unchanged historical partitions into the full candidate. The
contract checks that complete candidate. Add `dl_step_precheck()` immediately
after extraction when the incoming data also needs validation before Raw writes.

`dl_plan()` inspects the declared structure. It does not check actual data, SQL
translation, permissions or storage availability. Its `complete` attribute
means the declared sequence is structurally complete. Lineage records datasets
and releases; transformation names do not generate automatic column lineage.

## Inspect outcomes

Use `dl_status()` and `dl_quality()` for R run results and dbt results.
`dl_releases()` lists publication history, and `dl_lineage()` exposes recorded
dependencies. Metric results carry a manifest with the definition, parameters,
input release and result hash. These outputs keep the workflow inspectable as
additional components are introduced.

## Version definitions deliberately

An ID and version identify an immutable registered definition. Increase the
version when a source or contract changes. Since the pipeline embeds these
objects, increase its version too. Use a new `code_version` for changed
transformations, captured closure values or dependencies.

```r
# During development, before the first registration:
pipeline$version <- "1.1.0"
pipeline$code_version <- "new-git-sha"
```

Convenient update/remove helpers remain future work. Prefer reconstructing and
versioning definitions in an R script. Mutable specification lists are not a
stable extension contract for arbitrary third-party plugins.
