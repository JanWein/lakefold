# Architecture review: lakefold 0.7 to tidyweave 0.8

Baseline: commit `047f4cc`, reviewed on 20 September 2026. This is an experimental
development release. Compatibility commitments begin with the first stable
release candidate. The rename deliberately removes the old `dl_*` public API.

## What was already strong

The existing package had valuable guarantees: original input archives, immutable
lake releases, pinned report inputs, full-candidate quality checks and a release
marker committed together with lineage and successful run status. Its pointblank
integration preserved native thresholds and segmented evidence. DBI, dbplyr, dbt
and ordinary R functions offered useful escape hatches. These capabilities are
retained rather than replaced by a new storage engine.

## What needed to change

| Category | Previous weakness | Decision and practical effect |
|---|---|---|
| UX | A product constructor returned two different classes depending on its arguments. | One product class and named sources cover both direct and derived products. |
| API consistency | Several public execution and build paths competed for attention. | `run()` is the execution verb; `publish()` is the immediate storage shortcut. Low-level lake machinery is internal. |
| UX | Adding a source silently replaced the previous one. | Sources accumulate by name; replacing an existing name is explicit. |
| Coupling | The simple product path materialized database sources immediately. | DBI sources and compatible transformations retain lazy tables; inspection reveals materialization boundaries. |
| UX | Automatic contracts rejected factors; function predicates behaved differently from formulas. | Factor labels have character semantics without coercing the input object. Functions can return row-wise logical vectors. |
| UX | Explicit contracts silently enabled a 48-hour freshness policy. | Freshness is opt-in. Business deadlines are never inferred. |
| Architecture | Metadata delivery lived inside execution and was not recoverable independently. | Durable run evidence and a delivery outbox support retries without re-running data transformations. |
| Extension | Adapters lacked comparable capability declarations. | S3 interfaces and explicit capabilities expose supported operations and limits. |
| Integration | Useful ecosystem components required ad hoc callbacks. | Optional adapters cover DBI targets, Arrow/Parquet, pins, httr2, targets and metadata services. |
| Documentation | Parallel Markdown and vignette guides drifted, and advanced machinery leaked into the introduction. | Executable English vignettes are canonical. The README starts with an ordinary table and a few verbs. |

## Resulting model

The user describes a product: its sources, transformations, optional expectations
and destination. Ordinary tables, paths and functions remain valid inputs.
Internally, normalization establishes component semantics, validation checks the
definition, execution resolves dependencies, and adapters perform the work.

There is one execution lifecycle but different storage guarantees. An R result,
a replaceable database table, a pin and an immutable lake release are not
interchangeable guarantees. `capabilities()` and the integration guide make those
differences explicit. Selecting an adapter does not confer lake transactions on
an unrelated backend.

## Why this architecture

The external API follows tidyverse principles: readable verbs, ordinary R
objects, pipes and progressive configuration. Structural ideas from tidymodels
inform the inside: inspectable specifications, reusable composition, lifecycle
validation and replaceable implementations. Users do not need to understand
these internal layers to prepare and check a table.

The package coordinates mature tools. DBI provides connectivity, dbplyr pushes
queries into databases, Arrow reads columnar data, dbt manages SQL models,
pointblank evaluates specialist checks and targets manages dependency execution
and caching. There is no separate plugin registry or mandatory class for an
ordinary R function.

## Remaining boundaries

- A local lake and evidence directory require coordinated writers.
- Native R functions can require memory even when their input was lazy.
- Function closures and external services need explicit cache invalidation.
- dbt staging/build side effects are outside the final product publication gate.
- Metadata delivery is at least once and separate from data publication.
- Remote deployments need their own permissions, operational controls and tests.

See [modern-stack coverage](MODERN_DATA_STACK.md) for requirement-level boundaries
and [validation evidence](VALIDATION.md) for the checks actually performed.
