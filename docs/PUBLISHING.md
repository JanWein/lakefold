# GitHub publication, checks and releases

Project: [JanWein/tidyweave](https://github.com/JanWein/tidyweave).
Documentation: [tidyweave](https://janwein.github.io/tidyweave/).

The package is in active development. Public API compatibility starts with the
first stable release candidate; development changes may break earlier code.
Publishing a package version is distinct from `publish()`, which writes a checked
data product to its configured destination.

## Development and verification

Use a branch and pull request as described in [CONTRIBUTING.md](../CONTRIBUTING.md).
Keep package documentation, examples and user messages in English. Regenerate
function help from roxygen2 comments, and keep the vignettes executable.

The R-CMD-check workflow covers DuckDB and DuckLake on Linux, portable R/OS
configurations, and a core installation without optional infrastructure packages.
Full check jobs install Suggests, so installed SQLite, Arrow, pins, httr2 and
targets integrations participate in their tests. The Linux backend jobs install
a pinned dbt engine for real CLI integration tests. Tests of remote HTTP adapters
use local fixtures; deployment credentials and production services are not needed.

R packages and extensions are downloaded during setup; the environment is not
fully frozen. Consult the Actions results for the actual commit and
[VALIDATION.md](VALIDATION.md) for the recorded verification scope. A locally
successful test is not evidence that a later GitHub job or deployment passed.

## Documentation site

The Documentation workflow builds pkgdown into `site/` and deploys its artifact
to GitHub Pages. The installed package also includes function help and vignettes.
Locally, run `pkgdown::build_site()` after installing the documentation dependencies.
Review article links, examples and the reference index before deployment.

## Release preparation

Before a release candidate, update the version and NEWS, run the complete test
suite and `R CMD check`, verify examples and documentation, and record remaining
operating limits. Tag the reviewed commit with its actual version only after
required checks pass. Do not infer stability from a development version number.

Remote database, object-storage and catalog deployments require verification in
their own environments. A public GitHub repository contains package source and
synthetic examples, not production data, credentials or operational evidence.
