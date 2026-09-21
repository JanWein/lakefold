# API by task

| Task | Start with |
|---|---|
| Define and execute a product | `tw_product(name, data)`, `tw_trial()`, `tw_collect()` |
| Add preparation and expectations | Supported dplyr verbs, `tw_add_contract()`, `tw_add_quality()` |
| Enrich without multiplying rows | `tw_add_lookup(..., by = join_by(...))` |
| Accept a raw delivery | `data |> tw_ingest(to = ...)` |
| Build and approve SQL outputs | `tw_dbt_project(..., lake, sources) |> tw_run() |> tw_publish("model")` |
| Understand a definition | `tw_inspect()`, `tw_explain()`, `tw_validate()`, `tw_capabilities()` |
| Select persistence | `tw_set_target()`, `tw_publish()`, `target_*()` |
| Read execution evidence | `tw_status()`, `tw_quality()`, `tw_run_history()`, `tw_incidents()` |
| Deliver external metadata | `tw_add_catalog()`, `catalog_*()`, `tw_retry_catalogs()` |
| Reproduce an issued report | `tw_measure(published_result, metric)`, `tw_report_release()`, `tw_report_read()` |
| Start a project or dependency graph | `tw_init_project()`, `tw_as_targets()` |
| Implement an adapter | `tw_read_source()`, `tw_write_target()`, `tw_run_quality()` and S3 methods |

Arguments, return values and examples have one canonical home in the
[function reference](https://janwein.github.io/tidyweave/reference/index.html).
Learn the grammar with the [five lessons](https://janwein.github.io/tidyweave/articles/get-started.html).
