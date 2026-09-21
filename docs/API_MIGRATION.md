# One development grammar

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


Start with `tw_product(name, data)`. Add ordinary supported dplyr calls, checked
lookups with explicit equality keys, a contract or quality predicates. Execute
with `tw_run()` and get a table with `tw_collect()`. `tw_publish()` writes checked output;
`tw_ingest(data, to)` validates received input before RAW. Product ingestion accepts
one primary source and input checks, without transformations or a publication target.

Successful results can be sources directly. Lake results pin exact immutable
releases. Other results reuse their retained submitted table or lazy query;
they do not freeze a mutable database, file or remote source. For a DBI append
result, the reused table is the submitted batch. A product definition remains
instructions to execute. `tw_add_source(...,
replace = TRUE)` replaces a sole primary source; multiple primary sources need
an explicit source name. Lookup references are auxiliary dependencies.

Use `engine = "pointblank"` for simple quality predicates or `engine = "dm"`
for checked lookups. Defaults remain native. Custom agents, general transforms,
SQL, direct DBI and S3 adapters remain explicit escape hatches. Only supported
dplyr verbs have product methods; the package does not recreate the tidyverse.

Managed `tw_dbt_project(path, lake = config, sources = list(...))` prepares profiles
and exact bindings at execution. `tw_run()` builds and `tw_publish("model")` snapshots
a successful output. Other dbt adapters can keep explicit profiles. An approved lake
result is also a measurement context: `tw_measure(result, metric, ...)`.

This breaking development API has no compatibility aliases before its first
stable release candidate. Earlier lake-first `tw_ingest(lake, data)` calls become
`tw_ingest(data, to = lake)`. Stored immutable releases and report integrity remain
requirements. See the [design plan](UNIFIED_GRAMMAR_PLAN.md) and the
[canonical tutorial](https://janwein.github.io/tidyweave/articles/relational-insurance.html).
