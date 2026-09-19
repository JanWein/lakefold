# Migrating to lakefold

The R package and GitHub project have been named `lakefold` since version 0.3.0.

```r
remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)
library(lakefold)
```

Replace `library(dataloom)`, `dataloom::` and the package name in `renv.lock`, CI
and deployments with `lakefold`. Explicitly remove the old package if needed.
Avoid attaching both packages in one session because their exports share names.

The `dl_*` function names and S3 classes remain available. Existing catalogs can
be opened with the same explicit configuration. The YAML format identifier
`dataloom-contract`, the existing default S3 prefix and existing `DATALOOM_*`
environment variables remain compatible. Renaming the R package does not move
data.

Check saved R functions and RDS specifications for references to the old
namespace and recreate them where necessary. Changes to business logic still
require definition versions and a new `code_version`. Version 0.4.0 adds a
versioned, additive registry migration path.

A dbt project is an additional specification, separate from registered
`dl_product` definitions. `dl_execute(project)` delegates to `dl_dbt_build()`.
The resulting dbt relations are not automatically registered as immutable
lakefold releases.

## From 0.4.0 to 0.5.0

The simple API is additive: `dl_open()`, `dl_write()`, `dl_read()` and `dl_close()`.
Existing lakes still open with their original configuration; `dl_open()` does
not adopt or move unmarked catalogs. No additional registry migration is needed.
Existing explicit contracts and definition versions keep their fingerprints.
Owner, description and grain may now be omitted in new contracts.

`dl_write()` derives technical versions when omitted. It records a structural
schema after the first successful write, but no business approval. Supply an
explicit contract to change that schema or add rules, and keep supplying that
contract for later writes. Custom callbacks default to fresh evaluation.

`dl_run()` still reuses historical matching releases for idempotent retries.
`dl_write()` only reuses the current release so a successful write is reflected
by the next default read. `dl_run(cache = "current")` opts into that policy;
`cache = FALSE` forces fresh evaluation. Historical releases stay immutable.

## From 0.3.0 to 0.4.0

On connection, lakefold creates `_dl.schema_version` and transactionally migrates
quality metadata to schema 2. New fields are `engine`, `stage`, `segment` and
`details`. Existing evidence receives engine `legacy` and stage `candidate`.
Existing releases and definitions are preserved. Subsequent connections do not
repeat an already applied migration. Unknown newer schema versions are rejected.

Use lakefold 0.4.0 or later after migration. Automatic downgrades and migrations
of business data schemas are not implemented.

Existing pointblank rules retain `policy = "rule"`. Switching to
`policy = "agent"` requires new contract and pipeline versions. Native action
levels then determine the gate outcome. New input contracts and changed
transformation logic also require updated definitions and `code_version`.

`dl_dbt_publish()` is an explicit additional publication step. A dbt build alone
still creates no lakefold release. pointblank agents are retained in memory only
with `keep_agents = TRUE` and are never serialized into the registry. Metadata
exports now include segment labels.

## English documentation and examples

English is the canonical language for the README, guides, vignettes, function
help and example templates. `README.en.md` remains a link to the main README.
Example column names and descriptions are English. This documentation update
does not rename user assets, change existing contracts or migrate data. Adapt
copied templates to your actual source schema before running them.
