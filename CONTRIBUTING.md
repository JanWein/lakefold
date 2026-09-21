# Contributing

Use synthetic data in issues and pull requests. Explain the expected result,
actual result, package version and backend. Keep production extracts and runtime
credentials out of examples, logs and metadata.

## Develop and verify

```r
install.packages(c("remotes", "testthat", "roxygen2", "rcmdcheck", "pkgdown"))
remotes::install_deps(dependencies = TRUE)
roxygen2::roxygenise()
testthat::test_local(".")
source("scripts/check.R")
pkgdown::check_pkgdown()
```

Use the Posit package-development and testing skills, base R pipes, roxygen2
Markdown and testthat edition 3. Format R files with `air format .`. Generate
`man/` and `NAMESPACE`; do not edit them by hand. Add meaningful tests for changed
behavior, especially failed publication gates, transactions, ownership and
backend substitution. Update NEWS when visible behavior changes.

Run infrastructure suites sequentially. Exercise DuckDB and DuckLake with
`TIDYWEAVE_TEST_BACKEND=duckdb` and `TIDYWEAVE_TEST_BACKEND=ducklake`; enable the
DuckLake integration with `TIDYWEAVE_TEST_DUCKLAKE=true`. Real dbt tests use
`TIDYWEAVE_DBT_EXECUTABLE`. The core-only CI job runs `scripts/check-core.R`
without optional infrastructure. Keep external services out of normal examples.

## One canonical home for each tutorial

All package documentation and user-facing messages are English. The README is
the short introduction. **Executable vignettes are the canonical tutorials.**
`docs/` holds design decisions, operational notes and concise links to tutorials,
not a second copy of their prose. Function arguments and return types belong in
roxygen help. `_pkgdown.yml` groups beginner functions before advanced adapters.

The downloadable examples are extracted from the corresponding vignettes:

| Script | Source |
|---|---|
| `everyday_workflows.R` | `everyday-workflows.Rmd` |
| `create_ducklake.R` | `create-ducklake.Rmd` |
| `composing_products.R` | `composing-products.Rmd` |
| `monthly_reporting.R` | `getting-started.Rmd` |
| `custom_target.R` | `extending-tidyweave.Rmd` |
| `end_to_end.R` | Runs `composing_products.R` |
| `relational-insurance.R` | `relational-insurance.Rmd` |

Use `knitr::purl(..., documentation = 0)` after tutorial edits. Chunks requiring
user files, credentials or optional services use `purl = FALSE`. Add
`library(tidyweave)` only if the extracted chunks do not include it. The monthly
script guards its optional DuckDB dependency. The insurance vignette wraps its
extracted workflow in `run_relational_insurance()`: its hidden opening/closing
chunks use the knitr `tangle` option, and conditional execution chunks enable
extraction without running the CLI. Do not replace the visible steps with helper
wrappers or maintain a separate copy of the runner. Execute the changed vignette and
its generated script; assertions in examples should test meaningful outcomes.

## Design discipline

A new user should need only `product(name, data)`, ordinary dplyr verbs,
`run()` and `collect()`. Use `add_lookup()` for checked enrichment and optional
quality engines through the same predicate grammar.
Expose optional detail when it solves a real need. Use one product representation
and ordinary R values. Add S3 interfaces when another implementation can use them;
do not add classes merely for symmetry. Declare adapter limits and verify that a
failed quality gate does not invoke its writer.

The package is in development. Public interfaces can change without compatibility
aliases until the first stable release candidate. This does not excuse careless
handling of stored data: immutable releases, complete-candidate checks and pinned
report evidence remain integrity requirements. Document actual test coverage and
production boundaries without claiming untested guarantees.

## Unified grammar

Definitions are connection-free. Supported dplyr methods capture genuine dplyr
expressions and evaluate them only during execution. Do not implement a second
expression language or silently collect a lazy table to make an unsupported
operation pass. Document the supported verbs and use ordinary functions as the
escape hatch. `ingest(x, to)` accepts receipt data before transformations;
`publish(x, to, layer)` writes checked prepared data. Successful lake results
are pinned release sources; other results reuse submitted data or a lazy query
with its backend's mutability. `measure(lake_result, metric)` retains the lake
release identity.
Managed dbt projects own generated profiles and bindings, while normal SQL,
contracts and tests stay in the project. See [the design plan](https://github.com/JanWein/tidyweave/blob/main/docs/UNIFIED_GRAMMAR_PLAN.md).
