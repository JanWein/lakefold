# GitHub publication and CI

Project: [JanWein/lakefold](https://github.com/JanWein/lakefold).
Maintainer metadata uses the GitHub no-reply address. Use repository issues for
bug reports and improvement proposals.

## Development

```sh
git clone https://github.com/JanWein/lakefold.git
cd lakefold
```

In R, run `remotes::install_local(".", dependencies = TRUE)`. Contribute through
a branch and pull request; see [CONTRIBUTING.md](../CONTRIBUTING.md).
Keep documentation, examples, user-facing messages and repository materials in
English. The README is the canonical overview.

## Automated checks

`.github/workflows/R-CMD-check.yaml` checks both backends on Ubuntu with R 4.5.1
for pushes to `main` and pull requests. Actions installs R, system dependencies
and optional test packages. `rcmdcheck` fails the job on errors and warnings.
Logs are retained as Actions artifacts. DuckLake needs access to its extension
repository.

R packages and extensions are downloaded at runtime; the build environment is
not fully frozen. The Actions tab shows the status for a specific commit.
Historical local results are recorded in [VALIDATION.md](VALIDATION.md).

## Build the documentation

The `Documentation` workflow builds a pkgdown website and uploads `site/` as a
Pages artifact. Its deployment job publishes the result to the
[documentation site](https://janwein.github.io/lakefold/). The README and guides
remain available in the repository, and function help and vignettes also ship
with the installed package.

Locally, install `pkgdown`, then run `pkgdown::build_site()`. Regenerate function
help from roxygen2 comments when it changes. Check article titles, examples,
internal links and the grouped reference index before publication.

## Release

Before releasing, update the version and `NEWS.md`, then wait for the checks to
pass. Create a tag for the version being released, for example:

```sh
git tag v0.4.0
git push origin v0.4.0
```

Describe operating boundaries in the GitHub release. The current package
requires one coordinated writer. Production S3/PostgreSQL environments require
their own integration tests; package checks do not establish those environments'
operational behavior.
