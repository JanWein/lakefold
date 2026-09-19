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

## From 0.6.0 to 0.7.0

No registry migration is required: schema 3 and existing releases are retained.
Existing open/write/read, pipeline, derived-product, metric and dbt calls remain
supported. `dl_run()` and `dl_validate()` are now S3 generics with existing
argument names preserved. Extension methods should accept `...`.

DuckDB moved from Imports to Suggests. Install `duckdb` >= 1.5.5 explicitly for
existing lake workflows. Core data-frame workflows need no database package.

For new composition, begin with `dl_product("name")` and add ordinary inputs
with `dl_add_*()`. `dl_run()` defaults to in-memory execution; `dl_publish()`
uses the configured target or a local `lakefold` folder. Add a target to use
`dl_run()` for durable publication. See the composing-products guide.

Existing `dl_product(inputs = ..., build = ...)` calls keep pinned releases and
lazy tables. New composed transforms receive ordinary data frames. This avoids
silently changing established execution and memory behavior.

Composed products rerun by default. Set `code_version` before `cache = TRUE`;
that version must cover closures, imported code and dependencies. Explicit
product versions remain immutable once registered. Added quality rules derive
an effective contract version while the original explicit contract is registered
separately. Existing explicit contracts and quality rules cannot silently vanish
through a later automatic-schema write.

Native run evidence is in memory; lake ingestion evidence is durable. A catalog
failure is reported as a warning after data publication and does not undo a
committed release. Do not treat custom target output descriptors as lake release
IDs unless their adapter documents those semantics.

The shared boolean validator now raises `dl_invalid_argument`, rather than the
misleading dbt-specific condition class, for invalid flags across the package.

## From 0.5.0 to 0.6.0

Open an existing lake once with a writable 0.6.0 connection. The additive schema
3 migration creates `_dl.run_owners` to identify future writers. Existing assets,
releases, quality results and reports are retained. Older runs have unknown
writer ownership. After migration use 0.6.0 or later; a read-only connection
never performs a migration and requires a schema 3 catalog.

Recreate metric definitions and give previously registered metrics a new
`version`. Earlier versions stored abbreviated formula labels, which could
collide for distinct long formulas. Version 0.6.0 fingerprints the full expression
and its input declarations. It cannot reconstruct missing historical formula
text, so it refuses to reinterpret an old identity. Historical report values
remain readable with `dl_report_read()`; they are not recalculated or rewritten.
`code_version` must still cover dependencies and captured external values.

Existing automatically inferred integer schemas are verified against their old
fingerprint, then widened to numeric in a new automatic contract version on the
next write. Earlier releases and definitions keep their identities and values.
Explicit integer contracts remain strict. Spaced and quoted column names are
accepted; asset and schema names retain their existing restrictions.

Other additions are optional: `partition_by`, source functions, `read_only`,
`dl_compare()`, `dl_report_read()`, local quality exceptions and explicit recovery.
Metric owner, description and unit may be omitted. A metric with no time column
defaults to flow; with a time column it defaults to stock. Approval and code
version remain explicit when executing a governed metric.

Report retries compare release IDs, metric identities, parameters and values,
ignoring only `calculated_at`. A successful retry retains the first saved
calculation times. Readback uses JSON value types, including ISO date strings.

## From 0.4.0 to 0.5.0

The simple API is additive: `dl_open()`, `dl_write()`, `dl_read()` and `dl_close()`.
Existing lakes still open with their original configuration; `dl_open()` does
not adopt or move unmarked catalogs. No additional registry migration is needed.
Existing explicit contracts and definition versions keep their fingerprints.
Owner, description and grain may now be omitted in new contracts.
New local lakes require empty or nonexistent folders; custom layouts continue
to use their original configuration.

`dl_write()` derives technical versions when omitted. It records a structural
schema after the first successful write, but no business approval. Supply an
explicit contract to change that schema or add rules, and keep supplying that
contract for later writes, including after a blocked first run or a blocked
contract upgrade. Custom callbacks default to fresh evaluation.

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
