# API by task

| Task | Start with |
|---|---|
| Define and execute a product | `product()`, `add_source()`, `run()`, `collect()` |
| Add preparation and expectations | `add_transform()`, `add_contract()`, `add_quality()` |
| Understand a definition | `inspect()`, `explain()`, `validate()`, `capabilities()` |
| Select persistence | `set_target()`, `publish()`, `target_*()` |
| Read execution evidence | `status()`, `quality()`, `run_history()`, `incidents()` |
| Deliver external metadata | `add_catalog()`, `catalog_*()`, `retry_catalogs()` |
| Reproduce an issued report | `source_release()`, `metric()`, `report_release()`, `report_read()` |
| Start a project or dependency graph | `init_project()`, `as_targets()` |
| Implement an adapter | `read_source()`, `write_target()`, `run_quality()` and S3 methods |

Arguments, return values and examples have one canonical home in the
[function reference](https://janwein.github.io/tidyweave/reference/index.html).
Learn the grammar with the [product tutorial](https://janwein.github.io/tidyweave/articles/composing-products.html).
