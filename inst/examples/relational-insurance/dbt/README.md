# Relational insurance reporting

This ordinary dbt-duckdb project is part of the synthetic tidyweave example.
Run `insurance_dbt_project()` from `relational-insurance.R` to copy it and write a
local `profiles.yml`, exact staging-release source bindings and structural model
contracts. No credentials or physical release table names are stored here.

`core_policy_monthly` aggregates one policy-month row per policy independently
of transactions. `core_cash_monthly` aggregates transaction cash separately.
`monthly_performance` joins those aggregates at company, channel and month.
An unpaid policy stays in the policy denominator. Multiple payments never
multiply the policy count or premium due.

All three models have structural contracts exported with `dbt_contract()`.
Composite uniqueness, relationships and total reconciliation are ordinary SQL
data tests. They supplement the Pointblank and dm input/product checks; they do
not undo writes from earlier models if a later test fails.

Models are mutable. The separate `dbt_publish()` call snapshots an approved mart
for R metrics and issued reports. Coordinate writers between build and publish.
Close R lake connections before invoking the dbt CLI.

This demonstration uses synthetic EUR amounts, complete two-month snapshots,
static broker attributes and cash transactions assigned to their receipt month.
Its cash-to-due ratio is a teaching example, not a regulatory arrears definition.
