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
| `composing_products.R` | `composing-products.Rmd` |
| `monthly_reporting.R` | `getting-started.Rmd` |
| `custom_target.R` | `extending-tidyweave.Rmd` |
| `end_to_end.R` | Runs `composing_products.R` |

Use `knitr::purl(..., documentation = 0)` after tutorial edits. Chunks requiring
user files, credentials or optional services use `purl = FALSE`. Add
`library(tidyweave)` only if the extracted chunks do not include it. The monthly
script guards its optional DuckDB dependency. Execute the changed vignette and
its generated script; assertions in examples should test meaningful outcomes.

## Design discipline

A new user should need only `product()`, `add_source()`, `run()` and `collect()`.
Expose optional detail when it solves a real need. Use one product representation
and ordinary R values. Add S3 interfaces when another implementation can use them;
do not add classes merely for symmetry. Declare adapter limits and verify that a
failed quality gate does not invoke its writer.

The package is in development. Public interfaces can change without compatibility
aliases until the first stable release candidate. This does not excuse careless
handling of stored data: immutable releases, complete-candidate checks and pinned
report evidence remain integrity requirements. Document actual test coverage and
production boundaries without claiming untested guarantees.
