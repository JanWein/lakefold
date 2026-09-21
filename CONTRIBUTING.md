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

## Documentation

All documentation and user-facing messages are English. The README is the short
introduction. Nine executable vignettes cover the current lifecycle: get started,
recipes, workflows, quality, reports, integrations, dbt, one reference case and
extensions. Extend the relevant guide rather than adding overlapping tutorials.
Arguments and return values belong in roxygen help. Operational responsibilities
live in `docs/OPERATIONS.md`; do not keep completed plans or duplicate tutorials.

Build the site with `TIDYWEAVE_TEST_DUCKLAKE=true`, then run
`python scripts/check-site-links.py site`. PR builds provide a preview artifact;
main builds deploy to Pages. Remove obsolete pages and their incoming links.

Two downloadable examples are generated with `knitr::purl(documentation = 0)`:
`custom_target.R` from `extending-tidyweave.Rmd`, and `relational-insurance.R`
from `relational-insurance.Rmd`. The insurance vignette's hidden `tangle` chunks
wrap the script in `run_relational_insurance()`; set `run_stack <- FALSE` during
extraction. Keep visible steps and extracted code in sync. Other example scripts
exercise distinct integrations rather than repeat introductory tutorials.

## Design discipline

The recommended path is `tw_product()` for requirements, `tw_recipe()` and
`tw_step_*()` for preparation, and `tw_workflow()` for assembly. Bind a delivery
with `tw_trial(data = )`, then use `tw_publish()` and `tw_collect()` as needed.
Keep those responsibilities independently reusable. Use `tw_set_engine()` to
select an operation implementation and a target to select storage.
Expose optional detail when it solves a real need. Use one product representation
and ordinary R values. Add S3 interfaces when another implementation can use them;
do not add classes merely for symmetry. Declare adapter limits and verify that a
failed quality gate does not invoke its writer.

The package is in development. Public interfaces can change without compatibility
aliases, migration guides or stored-format upgrades before version 1.0. This does not excuse careless
handling of stored data: immutable releases, complete-candidate checks and pinned
report evidence remain integrity requirements. Document actual test coverage and
production boundaries without claiming untested guarantees.

## Unified grammar

Definitions are connection-free. Supported dplyr methods capture genuine dplyr
expressions and evaluate them only during execution. Do not implement a second
expression language or silently collect a lazy table to make an unsupported
operation pass. Document the supported verbs and use ordinary functions as the
escape hatch. `tw_ingest(x, to)` accepts receipt data before transformations;
`tw_publish(x, to, layer)` writes checked prepared data. Successful lake results
are pinned release sources; other results reuse submitted data or a lazy query
with its backend's mutability. `tw_measure(lake_result, metric)` retains the lake
release identity.
Managed dbt projects own generated profiles and bindings, while normal SQL,
contracts and tests stay in the project.
