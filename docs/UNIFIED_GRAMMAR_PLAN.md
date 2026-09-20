# A smaller product grammar

## Review

The core already separates product definitions, source and target adapters,
execution results, contracts and publication. Optional infrastructure is in
Suggests. Immutable lake releases and report evidence are valuable boundaries.
However, the insurance walkthrough needs 15 helpers to connect these parts.
Users must repeatedly translate between framework, dplyr, dm, Pointblank and
dbt syntax. The principal problem is repeated integration work, not a missing
framework object.

| Issue | Why it matters | Decision |
|---|---|---|
| UX: products cannot use ordinary dplyr verbs | Simple transformations need wrapper functions | Capture real dplyr calls on the existing product class |
| API: ingest is lake-first | Its pipe direction differs from publish | Make ingestion data-first |
| Coupling: accepted results need manual source reconstruction | Users maintain identifiers the framework already knows | Pin successful lake results; reuse submitted output for other targets |
| UX: simple quality rules expose engine syntax | Choosing Pointblank changes the whole example | One logical predicate syntax with an optional engine |
| Extension: checked enrichment requires hand-built dm plumbing | Cardinality and orphan rules are repeated | One checked lookup adapter with native and dm validation |
| Coupling: dbt needs manually generated profiles and source YAML | Users reconstruct connection and release metadata | Managed project configuration and exact source bindings |
| API: dbt output has a separate publication verb | One intention has two public workflows | S3 publish dispatch delegates to the existing guarded engine |
| UX: measures require connection and release bookkeeping | Results already identify those inputs | Accept a published result as the measure context |
| Documentation: infrastructure obscures business decisions | Readers cannot distinguish essential from incidental steps | Rewrite the insurance guide around the unified grammar |

## Target

Keep one product representation. Ordinary R values normalize into its source,
transform and quality components. Real dplyr methods capture expressions without
reading data; run and publish execute them. A lookup owns an auxiliary dependency
without changing the primary source from a table into a list. These dependencies
participate in validation, memoization, lineage and orchestration.

```r
raw <- product("payments", payments) |>
  add_contract(payment_contract) |>
  add_quality(~ cash_amount > 0, engine = "pointblank") |>
  ingest(to = config)

enriched <- product("enriched_payments", raw) |>
  add_lookup(policies, by = dplyr::join_by(policy_id, month), engine = "dm") |>
  dplyr::mutate(net_cash = cash_amount - fee) |>
  publish(to = config, layer = "staging")

built <- dbt_project("analytics", lake = config,
  sources = list(payments = enriched)) |>
  run()

approved <- built |>
  publish("monthly_performance", contract = mart_contract)
```

The public publish generic shares intent across products, tables and successful
dbt builds. The existing dbt snapshot engine retains its provenance and candidate
validation guarantees. This iteration does not disguise dbt as an arbitrary R
transform or add a second orchestrator. SQL models, custom Pointblank agents,
ordinary functions, source/target S3 adapters and explicit DBI remain escape
hatches.

All definitions remain connection-free. Definition inspection never evaluates
captured expressions. Execution metadata describes the actual adapters used.
Business grain, contracts, keys, metric approval and code versions stay explicit.
Data version integrity is preserved even though the development API can change.

## Work

- [x] Review current architecture, API, integrations and example friction.
- [x] Choose a small target grammar and document its constraints.
- [x] Add dplyr product methods, result sources, auxiliary dependencies and generic collection/publication.
- [x] Add interchangeable formula quality engines and checked lookup engines.
- [x] Add managed dbt project configuration, generalized bindings and result publication.
- [x] Simplify ingestion, local configuration and result-based measures.
- [x] Rewrite the canonical walkthrough and update reference documentation.
- [x] Review simplification, captured-expression identity, lineage and failure gates.
- [x] Verify minimal and advanced workflows, both lake backends, examples, tests and R CMD check.
- [x] Prepare the verified repository and documentation for publication.

Publication and cross-platform CI are tracked in the pull request for this change.
