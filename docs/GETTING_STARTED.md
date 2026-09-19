# Your first data product in ten minutes

This complete example uses synthetic data and requires no credentials. It runs
on the local DuckDB backend. To use DuckLake, set `backend = "ducklake"` in
`dl_config()`; the extension is loaded when connecting.

## Installation

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
library(lakefold)
library(dplyr)
```

R >= 4.2 is required. Lock dependencies in your own project for reproducibility.
This repository contains a development version; see the
[validation record](VALIDATION.md) for test evidence.

## 1. Create a delivery

```r
root <- tempfile("lakefold-tutorial-")
dir.create(root)
input <- file.path(root, "reserves.csv")
write.csv(data.frame(
  id = c("A", "B"),
  date = c("2026-08-31", "2026-08-31"),
  amount = c(100, 200)
), input, row.names = FALSE)
```

## 2. Define configuration and a contract

```r
config <- dl_config(
  dl_catalog_duckdb(file.path(root, "metadata.duckdb")),
  dl_storage_local(file.path(root, "data")),
  landing = file.path(root, "landing"),
  backend = "duckdb"
)

contract <- dl_contract(
  id = "finance.reserves_contract", version = "1.0.0",
  owner = "Finance", description = "Reserve in EUR per policy and business date",
  grain = "One policy at one business date",
  columns = c(id = "character", date = "Date", amount = "numeric"),
  key = c("id", "date"),
  rules = list(dl_rule("nonnegative", function(data) {
    counts <- data |>
      summarise(total = n(), failed = sum(as.integer(amount < 0), na.rm = TRUE)) |>
      collect()
    dl_quality_counts(counts$failed, counts$total)
  }))
)
```

`columns` declares expected R types. The reader must produce them; the contract
does not silently coerce invalid input. By default, every declared column is
required and non-null, and extra columns and empty deliveries are rejected.

## 3. Compose the source and workflow

```r
source <- dl_source("finance.csv", input, reader = function(path) {
  read.csv(path, colClasses = c("character", "Date", "numeric"))
})

pipeline <- dl_pipeline("finance.import", config, code_version = "tutorial-v1") |>
  dl_step_land(source) |>
  dl_step_extract() |>
  dl_step_transform(function(data) mutate(data, amount = amount * 1000),
                    id = "thousand_eur_to_eur") |>
  dl_step_validate(contract) |>
  dl_step_publish("finance.reserves")

pipeline
dl_plan(pipeline)
```

These calls assemble definitions. The next call opens the lake and reads the
source file. The original still contains 100 and 200; the published candidate
will contain EUR 100,000 and EUR 200,000.

## 4. Execute and read

```r
run <- pipeline |> dl_execute(business_date = "2026-08-31")
run

lake <- dl_connect(config)
dl_tbl(lake, "finance.reserves") |> collect()
```

Expect status `published`, two rows and a total of EUR 300,000. For a reproducible
read, specify `dl_tbl(lake, "finance.reserves", release = run$release_id)`.
`collect()` brings the result into R, so filter or aggregate in DuckDB first
where possible.

## 5. Calculate an approved metric

```r
reserve <- dl_metric(
  "finance.total_reserve", "finance.reserves",
  expr = sum(amount), time_column = "date", time_behavior = "stock",
  unit = "EUR", owner = "Finance", description = "Total reserve at the business date",
  approved = TRUE, code_version = "tutorial-v1"
)
value <- reserve |> dl_execute(lake, at = as.Date("2026-08-31"))
value
# value: 300000

dl_report_release(lake, "report-2026-08", list(reserve = value),
                  code_version = "tutorial-v1")
```

`approved = TRUE` records a declared business approval; it does not start an
approval process. The report release stores values and provenance. Rendering a
PDF or Word document is a separate operation.

## 6. Inspect quality and repeated execution

```r
again <- pipeline |> dl_execute(lake, business_date = "2026-08-31")
stopifnot(again$status == "cached", again$release_id == run$release_id)

dl_registry(lake, "runs")
dl_registry(lake, "quality_results")
dl_catalog_export(lake, file.path(root, "catalog.json"))
dl_disconnect(lake)
```

The same input, definitions and business date reuse the existing release.
A cache hit does not create new quality evidence. Use `dl_quality(again)` or
`dl_quality(lake, run_id = again$run_id)` to resolve the original checks.
A failed delivery never replaces published data.

## Further examples

* [Failures, corrections and historical releases](QUALITY_AND_HISTORY.md)
* [Products, joins, metrics and reports](PRODUCTS_AND_METRICS.md)
* [Definitions and execution in detail](WORKFLOWS.md)
* Full demo: `source(system.file("examples", "end_to_end.R", package = "lakefold"))`
* Catalog: install `shiny` and `bslib`, then call
  `dl_catalog(snapshot = file.path(root, "catalog.json"))`.

Wrap scheduled workflows in a function and close connections with
`on.exit(dl_disconnect(lake), add = TRUE)`.
