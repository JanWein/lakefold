# Architecture review: tidyweave 0.9 to 0.10

The 0.10.0 review focused on accessibility: keep the existing publication
integrity while removing repeated integration work from ordinary R workflows.
The implementation is still in development. See the
[design decisions](UNIFIED_GRAMMAR_PLAN.md),
[executable walkthrough](https://janwein.github.io/tidyweave/articles/relational-insurance.html)
and [validation record](VALIDATION.md) for scope and evidence.

## What was already strong

The package already separated product definitions, source and target adapters,
execution results and contracts. Optional integrations stayed optional. Lake
publication retained input archives, immutable releases, full-candidate gates,
lineage and pinned report evidence. Ordinary R functions, DBI, dbplyr, Pointblank
and dbt supplied useful extension paths. These boundaries were worth retaining.

The main weakness was the amount of code needed to connect them. The insurance
tutorial needed fifteen helpers, including repeated source binding, profile,
relationship and release bookkeeping. Readers had to understand infrastructure
before they could follow the business calculation.

## Important changes

| Previous issue | Result in 0.10.0 | Why it matters |
|---|---|---|
| Simple transformations needed wrapper functions | Real dplyr methods append deferred operations to the existing product | Familiar R expressions remain readable and execute against the actual table |
| Product construction required a separate source step | `product(name, data)` accepts ordinary inputs directly | A first useful definition is one call |
| Quality engine choice changed simple check syntax | One logical predicate can use native or Pointblank execution | Optional infrastructure does not dominate the common case |
| Relational enrichment required a hand-built dm model | `add_lookup()` checks equality keys, parent uniqueness and unmatched children, with native or dm validation | The primary row grain stays explicit without repeating constraint plumbing |
| Reusing accepted data required manual release references | Successful lake results normalize into pinned release sources | The framework carries identity it already knows; other results retain their submitted data or query |
| Ingestion's argument direction differed from other verbs | `data |> ingest()` and optional `to = "path"` | Simple receipt workflows need no configuration object |
| Local storage repeated several paths | `lake_config(path = ...)` adds explicit backend/layer choices | Advanced configuration remains possible without making it mandatory |
| dbt required repeated profiles and source YAML | Managed project specifications derive those bindings at execution | SQL models can focus on logical inputs while exact releases remain recorded |
| R and dbt outputs used different publication idioms | `run()` and `publish()` dispatch to the appropriate existing engine | The same intention uses the same verbs without rebuilding dbt inside R |
| Measurements required connection and release bookkeeping | `measure(approved_lake_result, metric)` retains the exact release | Consumer calculations can be pinned without repeating identifiers |
| Competing generic names depended on attachment order | `collect()`, `explain()` and `tbl()` reuse dplyr's generics | Familiar calls have one dispatch mechanism |
| The tutorial hid the workflow in integration helpers | Four business-definition helpers and one runner, extracted from visible vignette steps | Readers can see the actual data decisions in the public grammar |

## Resulting architecture

One product describes a primary table, ordered preparation, auxiliary lookup
dependencies, optional expectations and a destination. Normalization accepts
ordinary R values and successful results. Preflight validates the dependency
graph and adapter configuration. Execution reads and prepares data, checks it,
then delegates publication and evidence to their existing components.

A dplyr step captures an expression and its environment; it does not implement
another data-manipulation language. A lookup exposes its reference dependency
without turning the primary input into a named list. Source, transformation,
quality and target adapters remain replaceable. No second product class or
mutable platform object was introduced.

A managed dbt project is still a dbt project. Its ordinary SQL, model contracts
and data tests remain visible. A concise `dbt_contract()` export shares structural
metadata with R; unsupported business rules remain in the R gate or explicit SQL
tests. This bounded bridge is useful. Another managed-contract abstraction would
add a concept without removing the need to understand those limits.

## Remaining boundaries and tradeoffs

* Receipt checks and lake publication materialize data. Large-data execution
  requires compatible lazy transformations and an appropriate backend strategy.
* Lookups cover checked many-to-one equality relationships. Interval joins,
  allocation, CDC, streaming and cross-system movement need explicit designs.
* Captured environments and external state remain ordinary R behavior. Inspection
  is descriptive; caching needs deliberate code identity and invalidation policy.
* Lake results have immutable release guarantees. Other results reuse submitted
  tables or lazy queries; they do not freeze a mutable destination or live query.
* Managed dbt profiles cover local DuckDB and DuckLake. Remote adapters retain
  their own profiles, credentials and deployment checks. Model writes are not a
  transaction across the whole dbt graph.
* Report issuance remains an explicit registry write. Keys, time semantics,
  ownership, metric approval and publication policy are business choices.
* Scheduling, authorization, remote catalog operation and distributed recovery
  remain responsibilities of surrounding systems. Adapter availability is not
  proof of a production deployment.

The improvement is a smaller set of actions for users, backed by the existing
modular execution and publication guarantees. The earlier 0.7 to 0.8 architecture
review remains available in git history; this page describes the current review.
