# Everyday usability

> Historical development record. Examples and findings describe their original
> development stage. For current usage, follow [Get started](https://janwein.github.io/tidyweave/articles/get-started.html).


The public path is define, try, publish, correct, calculate and reopen. Familiar
R data and dplyr expressions remain the starting point. Infrastructure detail is
introduced by task, while business decisions stay explicit.

## Implementation and acceptance

- [x] Recommend one standard workflow in README and the executable everyday guide.
  Acceptance: a reader follows product, run, publish and collect without choosing
  among receipt and low-level storage interfaces.
- [x] Make results explain their checks and source evidence.
  Acceptance: a failed gate has an actionable status and diagnostic table;
  measurement diagnostics resolve the exact source release.
- [x] Reuse definitions for the next delivery.
  Acceptance: single-input data replacement and named graph replacements preserve
  contracts and transformations, reject unknown names and retain pinned inputs.
- [x] Retain explicit configuration once per product.
  Acceptance: execution defaults propagate with local overrides, destinations
  remain root-scoped and checking-engine changes preserve the declared contract.
- [x] Define related metrics together and separate exploration from issuance.
  Acceptance: shared settings avoid repeated metadata; report freezing requires
  explicit approval and code identity, even when exploration does not.
- [x] Organize documentation around user tasks.
  Acceptance: a canonical executable tutorial covers rejection, correction,
  comparison and immutable report readback; insurance retains real dbt boundaries.
- [x] Build all 14 vignettes and verify generated documentation and reference coverage.
- [x] Verify public examples and complete the final read-only implementation review.
- [x] Finish the installed-package regression suite and full package check.
  Result: 2,182 passed expectations, no failures or warnings; two optional
  OpenMetadata checks skipped. Final package check: no errors, warnings or notes.
- [x] Confirm the extracted insurance runner against the final implementation.
  Result: corrected January cash is EUR 1,230; the original report retains EUR 980.
- [x] Finalize the separate 0.12.0 validation record for review.

## Boundaries

This simplifies the API; it is not an independent usability study. Business keys,
partition replacement semantics, stock/flow meaning and report approval remain
explicit decisions. A configured run can write to its target. R graph replacement
does not automatically execute a separate dbt graph. A failed final gate does not
roll back prior independent writes. Lake and local evidence storage require one
coordinated writer, and publication materializes a complete candidate.

Numeric presentation and report serialization reject integer64 values outside
the exact double integer range when conversion is necessary. This protects
against silent rounding; it does not promise exact arbitrary arithmetic.
