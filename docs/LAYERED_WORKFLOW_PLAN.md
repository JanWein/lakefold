# Layered ingestion and dbt workflow

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


Baseline: tidyweave 0.8.0 (`64b2dfa`). This development increment closes the
specific source → input checks → raw → dbt staging/core/marts → approved release
→ consumers workflow. Integrations remain optional and documentation is English.

## Design

Use existing lake publication and dbt execution machinery. Add a small `tw_ingest()`
entry point for optional native/pointblank checks before RAW persistence. Keep
original landing deliveries even when checks reject data. Supply dbt with named,
explicit references to successful RAW releases rather than guessing generated
physical table names. Extend the dbt starter to staging, core and marts, with
real R-ingested sources and optional schema contracts. Consumer access uses a
successful immutable release; mutable dbt build relations are not approvals.

Integrate OpenMetadata's own dbt ingestion engine for dbt artifacts rather than
reimplementing its graph, test-result and column-lineage parsers. Metadata delivery
remains separate from data publication and retryable without rerunning dbt.

## Delivery checklist

- [x] Implement simple ingestion with optional input checks before RAW.
- [x] Bind accepted RAW releases to stable logical dbt source names.
- [x] Build a runnable raw/staging/core/marts starter and optional contract export.
- [x] Simplify checked dbt release publication and ordinary consumer access.
- [x] Integrate dbt artifact delivery through the optional OpenMetadata engine.
- [x] Exercise the entire workflow, rejected input and failed downstream checks.
- [x] Document Shiny, Quarto and Power BI consumption of approved outputs.
- [x] Run complete tests, examples, vignettes and R CMD check.

Publication, cross-platform checks and documentation deployment are tracked in
the corresponding GitHub pull request and [Actions runs](https://github.com/JanWein/tidyweave/actions).
They are verified after this source snapshot is uploaded.

## Boundaries

No distributed transactions, Power BI service provisioning or metadata-server
deployment. A generated connector configuration is not evidence of a live remote
deployment. Existing configurations stay explicit; the four-layer starter selects
its own layers without silently migrating stored lakes. No compatibility aliases
are required before the first stable release candidate.

## Review decisions

The previous components worked separately, but there was no small, explicit
bridge from an accepted R delivery to the dbt source graph. Final product checks
also occurred too late to serve as input acceptance. `tw_ingest()` now reuses the
existing pipeline with an input gate, while `tw_dbt_sources()` binds its immutable
result instead of exposing generated table-name guessing to users.

The starter adds normal dbt files, not another workflow object. `tw_dbt_contract()`
is deliberately a bounded schema bridge. The original R contract remains the
source of business rules that cannot be translated. `tw_dbt_publish()` supplies
structural defaults and a separate immutable approval boundary; it cannot turn
a multi-model dbt build into one database transaction.

The metadata hook accepts ordinary functions and S3 adapters. OpenMetadata uses
its own installed ingestion engine and separate delivery receipts. Database
inventory refresh remains an explicit prerequisite for newly created relations;
a zero CLI exit is not proof that every lineage edge was found.

Consumer workflows revealed one additional usability gap: `tw_source_release()`
now accepts configurations as well as open lakes. Configurations produce ordinary
data through owned read-only connections, and same-lake execution can safely
reuse its existing connection. Caller-owned sources retain lazy access.
