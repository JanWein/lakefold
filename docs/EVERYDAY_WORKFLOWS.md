# Everyday workflows

The [executable guide](https://janwein.github.io/lakefold/articles/everyday-workflows.html)
explains the common operations added in 0.6.0 with one local example.

| Need | Minimal operation |
|---|---|
| Replace a complete month while retaining others | `dl_write(lake, monthly, "orders", partition_by = "month")` |
| Reuse an existing API or database client | `dl_write(lake, fetch_orders, "orders")` |
| Compare current and previous data | `dl_compare(lake, "orders", key = "id")` |
| Analyze without registry writes | `dl_open("my-lake", read_only = TRUE)` |
| Read previously reported values | `dl_report_read(lake, "report-v1", values_only = TRUE)` |
| Inspect original rule exceptions locally | `dl_validate(data, contract, keep_errors = TRUE)` |
| Preview abandoned-run recovery | `dl_recover(lake, run_ids = interrupted_run_id)` |

The guide explains defaults, expected results and when an additional argument
is needed. Its source is [everyday-workflows.Rmd](../vignettes/everyday-workflows.Rmd).
Use the [operations guide](OPERATIONS.md) for recovery and the
[migration guide](MIGRATION.md) before upgrading an existing lake.
