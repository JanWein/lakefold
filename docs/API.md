# API by task

| Task | Start with |
|---|---|
| Define and execute a product | `product(name, data)`, `trial()`, `collect()` |
| Add preparation and expectations | Supported dplyr verbs, `add_contract()`, `add_quality()` |
| Enrich without multiplying rows | `add_lookup(..., by = join_by(...))` |
| Accept a raw delivery | `data |> ingest(to = ...)` |
| Build and approve SQL outputs | `dbt_project(..., lake, sources) |> run() |> publish("model")` |
| Understand a definition | `inspect()`, `explain()`, `validate()`, `capabilities()` |
| Select persistence | `set_target()`, `publish()`, `target_*()` |
| Read execution evidence | `status()`, `quality()`, `run_history()`, `incidents()` |
| Deliver external metadata | `add_catalog()`, `catalog_*()`, `retry_catalogs()` |
| Reproduce an issued report | `measure(published_result, metric)`, `report_release()`, `report_read()` |
| Start a project or dependency graph | `init_project()`, `as_targets()` |
| Implement an adapter | `read_source()`, `write_target()`, `run_quality()` and S3 methods |

Arguments, return values and examples have one canonical home in the
[function reference](https://janwein.github.io/tidyweave/reference/index.html).
Learn the grammar with the [five lessons](https://janwein.github.io/tidyweave/articles/get-started.html).
