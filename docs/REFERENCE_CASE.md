# Product direction and cancellation reference case

Decision record, 2026-09-21. The user chose synthetic customers, policies and
brokers, a cancellation rate, user-authored products and contracts, table and
multi-table products, and concurrent writers using DuckLake with PostgreSQL.
The executable business example is [cancellation-report.Rmd](../vignettes/cancellation-report.Rmd).

## Business decisions for the reference case

These are explicit example assumptions, not universal insurance conventions.

- Full snapshots include historical policies. Corrections replace a complete
  snapshot. Partial updates and reinstatements require a different input model.
- Customer, policy and broker IDs are unique, non-null strings. Policy references
  must exist. A policy may have only one inception and one cancellation.
- Cancellation is effective at the start of its date. Date order must be valid.
- Monthly cancellation rate uses a fixed opening cohort: policies beginning before
  the month and not cancelled before the month. The numerator contains only
  cancellations in that cohort during the month, with the end date excluded.
- New business in the month is excluded from both numerator and denominator.
- No exposure yields an undefined rate, not zero. The reference includes a
  zero-exposure channel test. Both undefined rates and entirely empty input
  currently fail tw_measure(); input na_policy does not permit missing outputs.
- Global rates are computed from counts, never by averaging channel rates.
- Broker/channel attributes use the supplied snapshot. Historical attribution
  would need effective-dated reference tables and explicit temporal joins.
- The three deliveries are individually named inputs, not three reporting months.
- Original output: 2 / 5 = 40%. Correction: 3 / 5 = 60%. Old report stays 40%.

## Reusable components and their boundaries

| Component | Responsibility | Current implementation |
|---|---|---|
| Contract | Types, grain, keys, required fields, business checks | tw_contract() |
| Table product | Named inputs, preparation, checks, publishable table | tw_product() |
| Relational model | Several tables and explicit PK/FK relationships | dm; tw_model() for lake releases |
| Model product | Named, versioned set of table releases and relationships | tw_product(dm), tw_trial(), atomic tw_publish(), tw_collect() |
| Metric | Reviewed formula, unit, grouping and missing-value policy | tw_metric(), tw_metric_set() |
| Report | Issued values and immutable evidence | tw_report_release() |
| Execution configuration | Storage and optional engines, separate from business logic | tw_lake_config(), tw_execution_config() |

A model remains several tables. `tw_product("report", result, table = "policies")`
selects a pinned member before transformation. No implicit flattening occurs.
All member tables, release records, relationships and the model manifest commit
in one transaction. Complete-model validation materializes member tables in memory.

## Shared deployment target and implementation

Use PostgreSQL for DuckLake catalog metadata and shared object storage for data.
The canonical setup guide is [Shared DuckLake](../vignettes/shared-ducklake.Rmd).
Package writes use PostgreSQL advisory locks through RPostgres; independent
clients can submit work while writes serialize at database scope. `previous`
rejects stale corrections. Direct SQL and external dbt materialization do not
participate in package coordination and must not modify managed releases.

The reference case uses the same contracts, products and metrics locally or with
shared configuration. Its derived reporting product is a separate atomic
publication pinned to one model release, not a transaction across the entire
reporting workflow. A later failure never changes the previous issued report.

The first implementation deliberately does not add concurrent write throughput,
a scheduler, authorization, implicit cross-table flattening or automatic business
approval. Shared landing evidence and S3 authentication are deployment concerns.

## Usability acceptance

An R/dplyr user authors the three contracts and products, finds P6, corrects it,
calculates the rate, publishes it, corrects P7 and retrieves the original report.
The ordinary path must not require internal release IDs or generated source names.
A second author must be able to reuse definitions with different deliveries and
storage configuration. Assess first-use usability with an independent person;
a scripted simulation establishes execution correctness, not learnability.

## Validation

The generated script, vignette and targeted regression tests exercise the
cancellation example with model products and preserved report values. Model tests
include rollback after an injected mid-publication failure, retained historical
members, stale corrections, missing references and diagnostic rows. Metadata
migration retains prior releases. PostgreSQL behavior is exercised by the
dedicated CI service and independent processes in scripts/check-postgres.R.
Check the PR's latest results for execution status; a script is not proof of a
successful run. Production S3 connectivity and a human first-use study remain
separate acceptance tasks.

The PostgreSQL CI run on commit
[5090db7](https://github.com/JanWein/tidyweave/commit/5090db758e6ce783c620b6148bf414a138eba048)
passed with PostgreSQL 16 and actual DuckLake. It exercised independent writers,
a conflicting correction, idempotent report issuance, a timed-out writer,
read-only access during a held lock, lock release after process termination,
nested publication and the model relationship gate. Shared files in this test
were local to one runner; this is not an S3 deployment test.
