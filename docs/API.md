# API map

The public interface uses `tw_` throughout. Start with independently reusable
components, then bind a delivery and execute.

| Responsibility | Main functions |
|---|---|
| Product requirements | `tw_product()`, `tw_add_contract()`, `tw_add_quality()` |
| Preparation instructions | `tw_recipe()`, `tw_step_*()`, `tw_lookup_spec()` |
| Component assembly | `tw_workflow()`, `tw_add_product()`, `tw_add_recipe()` |
| Component replacement | `tw_update_product()`, `tw_update_recipe()`, `tw_extract_recipe()` |
| Operation implementation | `tw_set_engine()` |
| Try or save a delivery | `tw_trial()`, `tw_run()`, `tw_publish()` |
| Data and evidence | `tw_collect()`, `tw_status()`, `tw_quality_report()`, `tw_lineage()` |
| Storage and integration | `tw_source_*()`, `tw_target_*()`, `tw_catalog_*()` |
| Metrics and reports | `tw_metric_set()`, `tw_measure()`, `tw_report_release()` |
| Extension protocols | `tw_read_source()`, `tw_execute_transform()`, `tw_write_target()` |

The [function reference](https://janwein.github.io/tidyweave/reference/index.html)
is the canonical source for arguments, returns and examples. Follow
[Get started](https://janwein.github.io/tidyweave/articles/get-started.html) for
one complete workflow, or the
[migration guide](https://janwein.github.io/tidyweave/articles/api-migration.html)
for existing code.
