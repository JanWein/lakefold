# Contributing

Create a focused issue or pull request with a reproducible example using
synthetic data. Describe the expected behavior, actual behavior, package versions
and backend. Do not attach credentials, production extracts or private catalog snapshots.

From the repository root:

```r
install.packages(c("remotes", "testthat", "roxygen2", "rcmdcheck"))
remotes::install_deps(dependencies = TRUE)
testthat::test_local(".")
Sys.setenv(DATALOOM_TEST_DUCKLAKE = "true")
testthat::test_local(".")
source("scripts/check.R")
```

Update roxygen comments and run `roxygen2::roxygenise()` for changed public APIs.
Add meaningful regression coverage for publication, idempotency and quality-gate
changes. Keep database identifiers quoted and credentials out of registry records.
Update `NEWS.md` and the relevant guide when behavior changes.

Write package documentation, examples, user-facing messages, issue templates
and repository materials in English. Keep the README as the canonical overview.
When guide content is shared between `docs/` and `vignettes/`, update both.
Keep `inst/examples/monthly_reporting.R` aligned with the core steps and result
assertions in `vignettes/getting-started.Rmd`. Execute both after tutorial edits.

Design for a short path through common tasks and explicit composition for more
complex workflows. Require only the inputs needed for the selected operation;
keep metadata and advanced integrations optional and document the defaults.
Keep sources, contracts, steps, products, metrics and releases
consistent in their inputs, outputs and lifecycle.

Core principles: explicit release identity, failed checks block publication,
normal R functions and tidyverse-compatible data objects, optional integrations,
and accurate statements about tested behavior.


The development workflow follows Posit `r-package-development`,
`testing-r-packages` and `critical-code-reviewer` skills. Use base pipes, format
with `air format .`, generate `man/` and `NAMESPACE` from roxygen2 (never edit
Rd manually), and run `pkgdown::check_pkgdown()`. Add new topics to the grouped
reference index. Tests use testthat edition 3 and clean up temporary files.

For the external dbt integration test, install the versions documented in the
dbt vignette and set `LAKEFOLD_DBT_EXECUTABLE` to the executable's absolute path.
Run both `DATALOOM_TEST_BACKEND=duckdb` and `ducklake`. Keep optional external
services out of ordinary examples; explain explicit integration requirements.
The generated docs use runnable offline examples, and CLI-only chunks are
clearly labelled. Full checks build vignettes instead of suppressing them.
