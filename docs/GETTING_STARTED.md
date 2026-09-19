# Getting started: open, write and read

Install the package and try the minimal local workflow:

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
library(lakefold)

orders <- data.frame(id = 1:3, amount = c(25, 75, 50))
lake <- dl_open("my-lake")
dl_write(lake, orders)
dl_read(lake, "orders")
dl_close(lake)
```

R >= 4.2 and DuckDB >= 1.5.5 are required. No remote service, credentials,
DuckLake extension, dbt or pointblank installation is needed for this workflow.
Reopen the same folder with `dl_open("my-lake")` in a later session.

`dl_write(lake, "orders.csv")` also reads files directly. CSV, TSV and RDS are
supported by default. Data-frame expressions need an explicit asset name:
`dl_write(lake, data.frame(id = 1:3), "orders")`.

The first successful write records column names and types. Later schema
changes and empty deliveries block publication and leave the previous release
available. Missing values are permitted; no business rules are inferred.

## Optional additions

* Add a contract for keys, business rules, ownership or freshness requirements.
* Add `reader` for other file formats or explicit parsing choices.
* Set `lazy = TRUE` in `dl_read()` to filter in the database before collecting.
* Supply `release` to read an exact historical version.
* Use `dl_config()` and `dl_pipeline()` for custom storage and explicit steps.
* Adopt pointblank, dbt, dm and metrics only when their capabilities are needed.

A custom contract needs an identifier and columns:

```r
contract <- dl_contract("orders.checked",
  columns = c(id = "integer", amount = "numeric"), key = "id")
lake <- dl_open("my-lake")
dl_write(lake, orders, contract = contract)
dl_close(lake)
```

Explicit contracts require non-missing declared columns by default. Continue
supplying the contract on subsequent writes so its checks remain active.
The simple API chooses technical versions automatically; custom callbacks run
again unless an explicit `code_version` enables reuse.

The canonical [executable getting-started guide](https://janwein.github.io/lakefold/articles/getting-started.html)
includes failure handling, file parsing, historical reads, reopen behavior,
cache semantics and the progression to advanced workflows. Its R chunks run
as part of the package check. See also the [API](API.md),
[workflow guide](WORKFLOWS.md) and [validation record](VALIDATION.md).
