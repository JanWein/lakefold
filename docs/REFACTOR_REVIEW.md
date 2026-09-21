# Architecture review: tidyweave 0.10 to 0.11

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


The 0.11.0 refactor removes repeated decisions and transitions from the existing
product grammar. It keeps genuine dplyr evaluation, optional infrastructure,
immutable lake releases and explicit business promises. This page records design,
not test results; see the [validation record](VALIDATION.md) for measured checks.

## Changes in everyday work

| Repetition in 0.10 | Result in 0.11 | Deliberate boundary |
|---|---|---|
| Engine arguments on each predicate and lookup | One explicit `execution_config()` passed to execution | A local engine overrides the default; no global context |
| Repeated target configuration | Optional execution destination/layer defaults | Defaults apply to the root only; untargeted dependencies stay in memory; receipt is always RAW |
| Full enriched contract definitions | `contract_update()` reuses columns and expectations under an explicit identity | Changed grain, removed columns and type changes require reviewed promises |
| One call per metric and month, then manual table assembly | Batch `measure()` and tidy `collect()` | Each-period and aggregate selection remain distinct; stocks still need one date |
| Manual report connection management | Configuration or existing folder accepted by report functions | Caller-owned connections remain caller-owned; issuance remains explicit |
| Reconstructed correction products and dbt projects | `replace_sources()` updates named inputs and nested product references | Pinned results are never implicitly refreshed |
| Different status and lineage access paths | Common outcome column and result lineage accessor | Native statuses and actual execution evidence are retained |
| All exported topics presented together | Everyday, integration and extension reference groups | Advanced adapter interfaces remain available |

The canonical [insurance tutorial](https://janwein.github.io/tidyweave/articles/relational-insurance.html)
now demonstrates these operations directly. Its downloadable runner is extracted
from the vignette. Monthly measurements are long tables, corrections reuse the
same definitions, and assertions compare the saved original report with its
initial values after a new release is issued.

## Composition decisions

An execution configuration is a small value, not an engine registry or mutable
platform. Selecting a quality engine through execution defaults leaves the
declared contract fingerprint unchanged. Execution evidence records the resolved
engine separately, while explicit product code identity reflects execution
changes. Contract composition is an explicit change to a promise,
not automatic semantic inference through arbitrary dplyr. Source replacement traverses the
known dependency graph without executing it; it does not add a scheduler.
Measurement sets hold the individual manifests needed for report integrity while
collection produces ordinary data for analysis. Collected values alone cannot
substitute for the original evidence when issuing a report.

No second product class, SQL language or expression evaluator is introduced.
Specialist Pointblank agents, ordinary R functions, direct DBI and normal dbt SQL
remain appropriate escape hatches. Native/Pointblank simple predicates share
normalization; source and target adapters retain their existing responsibilities.

## Remaining boundaries and tradeoffs

* Contract columns are not automatically renamed or derived through arbitrary
  transformations. Changed row grain and rules require a business decision.
* Batch measurement handles named metric sets and common scope. `.period` is a
  list column so both single and multiple selected dates remain unambiguous.
* Receipt gates and lake archival materialize data. Compatible lazy operations
  remain backend-dependent and do not imply streaming ingestion.
* Lookups cover checked many-to-one equality relationships. Interval joins,
  allocation and movement between unrelated backends require explicit design.
* Managed dbt handles local DuckDB/DuckLake profiles and source bindings. Remote
  adapters retain their credentials and deployment setup; dbt graph writes are
  not one transaction.
* Lake results and issued reports retain immutable references. Other results
  reuse submitted data or queries with their backend's mutability.
* Scheduling, authorization, remote catalog operations and coordinated writers
  remain responsibilities of surrounding systems. An adapter is not proof of a
  production deployment.

Earlier reviews remain available in git history. Current implementation choices
are tracked in [the coherent workflows plan](COHERENT_WORKFLOWS_PLAN.md).
