# Relational insurance reporting vignette (0.9.0 baseline)

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


This records the earlier implementation and its validation. The 0.10.0
[unified grammar plan](UNIFIED_GRAMMAR_PLAN.md) replaces the integration helpers
with direct product, lookup, dplyr and managed dbt calls. New verification belongs
in [VALIDATION.md](VALIDATION.md).

Build an English, executable tutorial for multiple synthetic deliveries,
Pointblank acceptance before RAW, real dm enrichment, independently contracted
data products, dbt reporting models and reproducible measures.

## Design

Three inputs contain broker attributes, monthly policy snapshots and individual
premium payments. Two months and several payments per policy make row grain and
time semantics visible. All names and values are fictional.

The R workflow accepts each delivery with a contract and Pointblank checks.
Named pinned release sources feed ordinary functions using dm primary and
foreign keys. Validate relationships before flattening many-to-one paths. Publish
two independently contracted staging products: one row per policy and month,
and one row per payment enriched with policy and broker attributes.

A normal bundled dbt project consumes these exact immutable product relations.
The current dbt_sources() helper is deliberately RAW-only, so the example writes
ordinary source YAML from exact publication IDs resolved through the public
release registry. Explain this
handoff explicitly rather than guessing physical names or changing core APIs.
dbt prepares and aggregates each grain independently in core, then joins the
monthly aggregates in a mart. Export supported contracts with dbt_contract(), add
relationship/reconciliation tests, and publish the successful mart separately.
Governed R metrics and an issued report pin that approved mart release.

Explain stocks versus flows, weighted ratios, zero denominators, static broker
attributes, full-snapshot deliveries, memory boundaries and process-owned
connections. Demonstrate rejected input, an invalid relationship and a corrected
delivery without changing the old published report.

## Work

- [x] Add synthetic inputs, dm transformations and the runnable DuckLake example.
- [x] Add a small dbt project, contracts and independent expected-value checks.
- [x] Write a detailed vignette with diagram, code and explained output tables.
- [x] Link the guide from README and pkgdown navigation.
- [x] Execute the complete example and verify the rendered vignette and package.
- [x] Prepare the reviewed changes for GitHub and documentation publication.

## Verification

The complete runner and the vignette's separate stages both passed with real
DuckLake and dbt. Each of the two builds completed three models and twenty data
tests. The independent DuckDB integration scenario passed all 81 expectations.
The full package suite passed 1,497 expectations without skips. R CMD check,
including examples and all fourteen vignettes, reported zero errors, warnings
or notes. The diagram was rendered and visually reviewed.

Publication and deployment outcomes are recorded by the pull request and GitHub
Actions checks, rather than predicted by this implementation checklist.

The default full example uses DuckLake. A DuckDB option is available only for
testing and environments without extension access. Optional integrations remain
optional for package installation; the complete vignette documents its own
prerequisites. No production infrastructure or customer data is required.
