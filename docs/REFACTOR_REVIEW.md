# Architecture review and refactoring plan

Review baseline: lakefold 0.6.0, commit `014e799`, 19 September 2026.
This design was recorded before implementation. See the architecture guide and
validation record for the resulting behavior and verified scope.

## Current architecture map

| Surface | Current implementation |
|---|---|
| Public API | 70 exports; local open/write/read shortcuts; explicit ingestion steps; derived products; metrics; dbt; inspection and operations |
| Core objects | Small S3 lists for configuration, source, contract, pipeline, product, metric and run result; ordinary tables and functions |
| Execution | File landing, extraction, optional input gate and transformations, candidate composition, contract validation, atomic release marker |
| Internal abstractions | Shared candidate/publication helpers and `dl_execute()` S3 dispatch; most component operations are private functions |
| Integrations | DuckDB/DuckLake storage; DBI/dbplyr; pointblank; dbt CLI; dm; Shiny; S3 originals; YAML exports |
| Dependencies | DuckDB is mandatory; specialist quality, modeling, UI and CLI packages are optional |

The review covered the exported API, all R modules, test coverage, object and
execution boundaries, reference documentation, README, guides, examples and CI.

## Strengths worth retaining

- Publication gates fail closed and preserve the last successful release.
- Immutable input archives, pinned input releases and report manifests support
  investigation and reproducibility.
- The release marker, lineage and successful run status commit together.
- Ordinary R callbacks, DBI and dbplyr already provide useful escape hatches.
- Regression coverage includes rollback, history, read-only access, recovery,
  optional pointblank semantics and real dbt execution.

## Findings and decisions

| Category | Finding and consequence | Refactoring decision |
|---|---|---|
| UX | A composed import requires configuration, source IDs, code versions and four ordered steps before it is useful. | Add composition to the existing product constructor; accept ordinary inputs and optional additions. |
| API consistency | `dl_run()` accepts only pipelines; `dl_validate()` cannot check definitions; printing exposes technical step tables. | Make execution and validation dispatch by object; add concise inspection and explanation. |
| Architecture | Product and pipeline preparation are separate; the reliable release machinery is intertwined with its database. | Normalize a small product specification and compile it to the existing governed executor for lake targets. Provide a native executor for ordinary R and custom targets. |
| Coupling | Core quality validation branches on engine strings; even the shared boolean validator lives in the dbt module. | Introduce quality S3 dispatch and move shared validation into utilities. Preserve existing serialized rule identities. |
| Extension | Adding a source, transform, quality engine or target requires private knowledge or editing core functions. | Publish documented S3 component interfaces and test independently registered external methods. |
| Dependency | Installing and using the core requires DuckDB even for data-frame checks. | Make DuckDB optional, validate its availability only for lake execution, and verify an installation without it. |
| Documentation | The introduction is understandable for monthly files but undersells other uses and gives insufficient extension guidance. | Explain the small grammar first, then the internal model, capability differences and extension contracts. |
| Testing | Strong storage integrity tests do not prove backend-independent composition or extension behavior. | Add normalization, preflight, native execution, adapter substitution, result metadata and failure-path tests. |

## Target design

Beginner grammar:

```r
orders <- dl_product("orders") |>
  dl_add_source(data.frame(id = 1:2, amount = c(25, 75)))
orders |> dl_run() |> dl_collect()
orders |> dl_publish(to = "reporting-lake")
```

Optional additions: `dl_add_transform()`, `dl_add_contract()`,
`dl_add_quality()`, `dl_add_target()` and `dl_add_catalog()`.
`dl_validate()` performs preflight without reading data; `dl_plan()` and
`dl_inspect()` reveal definitions and execution choices.

Internally, convenient inputs become source/transform/quality/target components.
A product holds only composition and identity. Execution is selected by its
target: the native executor handles ordinary R and custom destinations; the
lake adapter compiles to existing immutable landing and publication machinery.
Both use the same component interfaces and return structured run evidence.
Contracts and quality remain independently usable on ordinary tables.

Extension interfaces cover source reads, transformations, quality evaluation,
target execution/writes, component preflight and metadata publication. No global
plugin registry, class for every function, generic scheduler or distributed
transaction protocol is introduced. DBI connections remain caller-owned.

## Deliberate boundaries

Native execution is in memory. Its run evidence is returned to the caller;
a lake target provides durable history and governed publication. Custom targets
must describe their persistence and atomicity guarantees. Adding a custom
adapter does not confer DuckLake transactions or immutable history on it.

Existing advanced pipelines and derived-product calls remain supported. Their
historical fingerprints and storage semantics are retained. Backend-specific
configuration stays in adapters. dbt continues to own its build graph and CLI
lifecycle; pointblank continues to own its advanced assertions. Remote production
services require environment-specific verification.
