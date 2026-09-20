# Capability index for tidyweave 0.10.0

Start with one named product and an ordinary R table. Add an integration only
when it supplies a capability you need. The package is experimental; its public
API may change before the first stable release candidate.

| Need | Available entry points | Guide |
|---|---|---|
| Compose and inspect a workflow | `product(name, data)`, dplyr verbs, `add_lookup()`, `validate()`, `inspect()`, `run()` | [Composition](https://janwein.github.io/tidyweave/articles/composing-products.html) |
| Read ordinary or remote data | Tables, callbacks, files, `source_database()`, `source_parquet()`, `source_api()`, `source_pins()`, `source_release()` | [Integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html) |
| Choose storage | `target_lake()`, `target_database()`, `target_parquet()`, `target_pins()` | [Integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html) |
| Define trustworthy data | `contract()`, `quality_rule()`, `quality_reference()`, `pointblank_checks()`, `profile_data()` | [Quality gates](https://janwein.github.io/tidyweave/articles/quality-gates.html) |
| Preserve lake history | Immutable releases, full-candidate gates, complete partition replacement, original archives | [Everyday workflows](https://janwein.github.io/tidyweave/articles/everyday-workflows.html) |
| Explain attempts and failures | `status()`, `quality()`, `run_history()`, `read_run()`, `incidents()`, quality reports | [Quality and history](https://janwein.github.io/tidyweave/articles/quality-history.html) |
| Reproduce calculations | Pinned sources, `model()`, `metric()`, `measure()`, `report_release()`, `report_read()` | [Products and metrics](https://janwein.github.io/tidyweave/articles/products-metrics.html) |
| Reuse ecosystem execution | `sql_transform()`, `transform_dbt()`, `as_targets()` | [Integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html) |
| Publish catalog metadata | `catalog_openlineage()`, `catalog_openmetadata()`, retryable catalog delivery | [Integrations](https://janwein.github.io/tidyweave/articles/optional-integrations.html) |
| Prepare a project | `init_project()`, optional renv and scheduling templates | [Getting started](https://janwein.github.io/tidyweave/articles/getting-started.html) |
| Add an implementation | S3 adapters, preflight, capabilities and conformance checks | [Extension guide](https://janwein.github.io/tidyweave/articles/extending-tidyweave.html) |

The same product composition accepts R, lazy DBI and Arrow data. Transformations
must support the objects they receive; a callback can explicitly collect data
when local R computation is appropriate. Quality and profiling push supported
operations to the backend.

Lake guarantees do not automatically apply to other targets. Inspect adapter
capabilities and documentation for transaction, overwrite, materialization and
history behavior. Remote service configuration needs verification in the
deployment environment.

The [modern data stack assessment](MODERN_DATA_STACK.md) distinguishes delivered
capabilities, operational requirements and deliberate boundaries, including the
comparison with Ab Initio. tidyweave integrates existing engines; distributed
scheduling, enterprise IAM, a visual ETL editor and a streaming engine are not
part of its core.
