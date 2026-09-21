# Coherent everyday workflows

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


Follow-up to PR #11, based on b0e214d. Use the Posit package-development,
testing and implementation skills. Keep one product representation, genuine
dplyr evaluation, optional infrastructure, immutable lake releases and explicit
business decisions. No implicit collection or mutable global configuration.

- [x] Batch measurements: explicit per-period versus aggregate selection,
  tidy collected values, retained individual manifests and safe report issuance
  using an owned configuration connection or a borrowed caller connection.
- [x] Execution defaults: explicit quality and relationship engine defaults
  propagated through product dependencies; local choices win. Target/layer
  defaults apply only to the root, never overwrite a dependency's target.
- [x] Contract composition: reuse and extend columns with explicit identity,
  safe handling of keys, rules and changed grain; common rule normalization.
- [x] Correction workflows: replace named product dependencies without manually
  reconstructing the graph; retain pinned result semantics; support managed
  dbt source replacement using existing objects.
- [x] Result inspection: consistent status categories and result lineage while
  retaining native statuses and existing quality diagnostics.
- [x] Documentation: update canonical executable insurance vignette and extract
  its runner; group reference into everyday, integration and extension use.
- [x] Verification: focused regressions, full package tests, DuckDB/DuckLake,
  actual dbt example, roxygen, pkgdown coverage and R CMD check.
- [x] Commit reviewable implementation, documentation and validation changes.
- [ ] Push the branch and create a follow-up PR without merging main.
  Publication awaits explicit authorization; local implementation is complete.

Implementation details and verified limitations belong in the final review and
validation record. New APIs must remove demonstrated repetition; avoid building
a second scheduler, SQL language or authorization system.
