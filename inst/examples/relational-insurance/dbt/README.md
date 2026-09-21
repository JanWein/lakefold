# Relational insurance reporting

This ordinary dbt-duckdb project accompanies the synthetic dataraft tutorial.
Copy it to a working directory, then define
`dr_dbt_project(path, lake = config, sources = published_products)`.
`dr_run()` prepares the managed connection profile and exact release bindings.
The models reference logical sources `inputs.policies` and `inputs.payments`.
No credentials or physical release identifiers belong in these tracked SQL files.

`core_policy_monthly` aggregates policy-month observations independently of
transactions. `core_cash_monthly` aggregates receipts. `monthly_performance`
combines the unique company-channel-month aggregates without multiplying policy
counts or premium due by the number of payments. Unpaid groups remain visible.

The walkthrough exports its R structural contracts with `dr_dbt_contract()` into
`models/contracts.yml`; all three SQL models enforce these schemas and not-null
data tests without maintaining the column definitions twice. Composite uniqueness, receipt-month relationships and
total reconciliation are ordinary SQL tests. The R mart contract keeps its
business rules and key checks. A failed dbt test does not undo earlier model
writes. `built |> dr_publish("monthly_performance", contract = mart_contract)`
approves an immutable snapshot for metrics and reports. Coordinate writers
between build and publication and close caller-owned R connections before dbt.

Amounts are synthetic EUR; snapshots cover two complete months, broker attributes
are static and payments are assigned to receipt month. The cash-to-due ratio is
an example metric, not a regulatory arrears definition.
