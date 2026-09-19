# API in 0.7.0

## Start with composition

```r
dl_product("orders") |>
  dl_add_source(data.frame(id = 1:2, amount = c(10, 20))) |>
  dl_add_transform(function(data) transform(data, amount = round(amount, 2))) |>
  dl_add_quality(~ amount >= 0) |>
  dl_run() |>
  dl_collect()
```

Optional additions are `dl_add_contract()`, `dl_add_target()` and
`dl_add_catalog()`. `dl_publish()` adds a default local target for durable
storage. `dl_validate()` checks definitions or evaluates data against contracts;
`dl_plan()`, `dl_inspect()` and `dl_explain()` describe intent without execution.
The reference index separates this small grammar from extension interfaces.

`dl_source_database()` describes DBI tables/queries; `dl_sql()` describes an
optional DuckDB SQL transform. `dl_target_lake()` isolates lake-specific options.
S3 source, transform, quality, target and catalog interfaces are documented in
the extension guide. The existing APIs below remain supported.

## Existing lake and specialist operations


New to the package? Read [Why lakefold?](WHY_LAKEFOLD.md), then follow the
[monthly reporting walkthrough](GETTING_STARTED.md) before browsing all functions.

The complete grouped reference is available on the [documentation website](https://janwein.github.io/lakefold/reference/index.html).
All 70 exported functions have package help. In R, use `help(package = "lakefold")`.

Start with `dl_open()`, `dl_write()`, `dl_read()` and `dl_close()`.
Configuration and business contracts are optional on this path. Existing
function names remain available. Input checks are optional; the final
publication check is mandatory. `dl_status()` and `dl_quality()` provide common
diagnostics. See the [quality guide](https://janwein.github.io/lakefold/articles/quality-gates.html) for worked examples.

| Function | Help topic |
|---|---|
| `dl_build()` | [dl_build.Rd](../man/dl_build.Rd) |
| `dl_capabilities()` | [dl_capabilities.Rd](../man/dl_capabilities.Rd) |
| `dl_catalog()` | [dl_catalog.Rd](../man/dl_catalog.Rd) |
| `dl_catalog_duckdb()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_catalog_export()` | [dl_catalog_export.Rd](../man/dl_catalog_export.Rd) |
| `dl_catalog_postgres()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_check_delivery()` | [dl_check_delivery.Rd](../man/dl_check_delivery.Rd) |
| `dl_cleanup()` | [dl_cleanup.Rd](../man/dl_cleanup.Rd) |
| `dl_close()` | [dl_open.Rd](../man/dl_open.Rd) |
| `dl_commons_yaml()` | [dl_commons_yaml.Rd](../man/dl_commons_yaml.Rd) |
| `dl_compare()` | [dl_compare.Rd](../man/dl_compare.Rd) |
| `dl_config()` | [dl_config.Rd](../man/dl_config.Rd) |
| `dl_connect()` | [dl_setup.Rd](../man/dl_setup.Rd) |
| `dl_contract()` | [dl_contract.Rd](../man/dl_contract.Rd) |
| `dl_contract_confirm()` | [dl_contract_confirm.Rd](../man/dl_contract_confirm.Rd) |
| `dl_contract_diff()` | [dl_contract_diff.Rd](../man/dl_contract_diff.Rd) |
| `dl_contract_from()` | [dl_contract_from.Rd](../man/dl_contract_from.Rd) |
| `dl_contract_yaml()` | [dl_contract_yaml.Rd](../man/dl_contract_yaml.Rd) |
| `dl_dbt_build()` | [dl_dbt_build.Rd](../man/dl_dbt_build.Rd) |
| `dl_dbt_init()` | [dl_dbt_init.Rd](../man/dl_dbt_init.Rd) |
| `dl_dbt_lineage()` | [dl_dbt_lineage.Rd](../man/dl_dbt_lineage.Rd) |
| `dl_dbt_model()` | [dl_dbt_model.Rd](../man/dl_dbt_model.Rd) |
| `dl_dbt_project()` | [dl_dbt_project.Rd](../man/dl_dbt_project.Rd) |
| `dl_dbt_publish()` | [dl_dbt_publish.Rd](../man/dl_dbt_publish.Rd) |
| `dl_dbt_status()` | [dl_dbt_status.Rd](../man/dl_dbt_status.Rd) |
| `dl_dbt_test()` | [dl_dbt_build.Rd](../man/dl_dbt_build.Rd) |
| `dl_disconnect()` | [dl_disconnect.Rd](../man/dl_disconnect.Rd) |
| `dl_execute()` | [dl_execute.Rd](../man/dl_execute.Rd) |
| `dl_expect_quality()` | [dl_expect_quality.Rd](../man/dl_expect_quality.Rd) |
| `dl_freshness()` | [dl_freshness.Rd](../man/dl_freshness.Rd) |
| `dl_ingest()` | [dl_ingest.Rd](../man/dl_ingest.Rd) |
| `dl_ingest_data()` | [dl_ingest_data.Rd](../man/dl_ingest_data.Rd) |
| `dl_interrupted()` | [dl_interrupted.Rd](../man/dl_interrupted.Rd) |
| `dl_lineage()` | [dl_lineage.Rd](../man/dl_lineage.Rd) |
| `dl_measure()` | [dl_measure.Rd](../man/dl_measure.Rd) |
| `dl_metric()` | [dl_metric.Rd](../man/dl_metric.Rd) |
| `dl_model()` | [dl_model.Rd](../man/dl_model.Rd) |
| `dl_open()` | [dl_open.Rd](../man/dl_open.Rd) |
| `dl_pipeline()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_plan()` | [dl_plan.Rd](../man/dl_plan.Rd) |
| `dl_pointblank()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_pointblank_report()` | [dl_pointblank_report.Rd](../man/dl_pointblank_report.Rd) |
| `dl_product()` | [dl_product.Rd](../man/dl_product.Rd) |
| `dl_quality()` | [dl_quality.Rd](../man/dl_quality.Rd) |
| `dl_quality_counts()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_quality_errors()` | [dl_quality_errors.Rd](../man/dl_quality_errors.Rd) |
| `dl_quality_report()` | [dl_quality_report.Rd](../man/dl_quality_report.Rd) |
| `dl_read()` | [dl_read.Rd](../man/dl_read.Rd) |
| `dl_recover()` | [dl_recover.Rd](../man/dl_recover.Rd) |
| `dl_register()` | [dl_register.Rd](../man/dl_register.Rd) |
| `dl_registry()` | [dl_registry.Rd](../man/dl_registry.Rd) |
| `dl_releases()` | [dl_releases.Rd](../man/dl_releases.Rd) |
| `dl_report_read()` | [dl_report_read.Rd](../man/dl_report_read.Rd) |
| `dl_report_release()` | [dl_report_release.Rd](../man/dl_report_release.Rd) |
| `dl_rule()` | [dl_rule.Rd](../man/dl_rule.Rd) |
| `dl_run()` | [dl_run.Rd](../man/dl_run.Rd) |
| `dl_setup()` | [dl_setup.Rd](../man/dl_setup.Rd) |
| `dl_source()` | [dl_source.Rd](../man/dl_source.Rd) |
| `dl_status()` | [dl_status.Rd](../man/dl_status.Rd) |
| `dl_step_extract()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_land()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_precheck()` | [dl_step_precheck.Rd](../man/dl_step_precheck.Rd) |
| `dl_step_publish()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_step_transform()` | [dl_step_transform.Rd](../man/dl_step_transform.Rd) |
| `dl_step_validate()` | [dl_pipeline.Rd](../man/dl_pipeline.Rd) |
| `dl_storage_local()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_storage_s3()` | [dl_catalog_duckdb.Rd](../man/dl_catalog_duckdb.Rd) |
| `dl_tbl()` | [dl_tbl.Rd](../man/dl_tbl.Rd) |
| `dl_validate()` | [dl_validate.Rd](../man/dl_validate.Rd) |
| `dl_write()` | [dl_write.Rd](../man/dl_write.Rd) |
