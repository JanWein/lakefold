# lakefold

**Turn recurring files into checked data that your reports can trust.**

Every month, a spreadsheet arrives. You read it, check it and calculate a number.
Then a correction arrives. Which data should tomorrow's report use, and how do
you explain the number in the report you already sent?

lakefold gives this workflow a repeatable home in R. It keeps the submitted
input, checks the proposed table, and makes a new version available only when
its publication checks pass. You can read the latest successful version or
return to the exact version used earlier.

**Start with the explanation, then try the same story yourself:**

1. [Why lakefold? From monthly files to reliable reports](https://janwein.github.io/lakefold/articles/why-lakefold.html): the problem, the benefit, a diagram and the concepts in plain language.
2. [Build a monthly reporting workflow, step by step](https://janwein.github.io/lakefold/articles/getting-started.html): store August's 350, correct it to 370, reject a duplicate, add September and reproduce the original report.

## A useful first step

Install once with R >= 4.2:

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
```

Then use an ordinary R table:

```r
library(lakefold)
reserves <- data.frame(entity = c("North", "South"), amount = c(100, 250))

lake <- dl_open("my-reporting-lake")
first <- dl_write(lake, reserves)
dl_read(lake, "reserves")
# North: 100, South: 250. Total: 350.

dl_close(lake)
```

Reopen the same folder with `dl_open("my-reporting-lake")` in a later session.
A dedicated local folder is enough. DuckDB >= 1.5.5 is a normal package
dependency; servers, credentials and optional integrations are unnecessary for
this example. CSV, TSV and RDS files can also be submitted directly. The
walkthrough shows how to read and preserve an Excel workbook.

The first successful write remembers column names and types. Automatic numeric columns accept integers and decimals; explicitly declared
integer contracts stay strict. Later incompatible schema
changes and empty deliveries block publication, leaving the last successful
version available. Missing values are allowed on this basic path. Business
checks, such as one row per entity and date, are rules you add explicitly.

## What does this buy you?

| In your reporting work | With lakefold |
|---|---|
| A correction changes a number | Read the corrected data and retain the earlier version |
| A delivery violates a declared check | Inspect the failure while reports keep the last successful data |
| Someone asks where a figure came from | Inspect its input releases, checks and processing records |
| Several reports repeat the same preparation | Optionally define one reusable product or metric |
| The workflow grows | Add explicit steps while keeping ordinary R functions and tables |

A **release** is a checked version of a table. Publishing a release makes it
readable in your lake; it does not put your data on the public internet.

## Add only what you need

You can stop at writing and reading one dataset. Each addition answers a
specific need:

| Need | Next addition |
|---|---|
| Reject duplicate records or invalid values | A contract, optionally with pointblank rules |
| Use a previous version | `release = first$release_id` in `dl_read()` |
| Keep several complete months in the current table | `dl_write(..., partition_by = "date")` |
| See which records and totals changed | `dl_compare(lake, "reserves", key = "entity")` |
| Analyze without changing metadata | `dl_open("my-lake", read_only = TRUE)` |
| Reopen a saved report | `dl_report_read(lake, "report-id")` |
| Fetch from an existing API or database client | `dl_write(lake, fetch_data, "orders")` |
| Reuse a prepared table | A product built from recorded input releases |
| Record the meaning and inputs of a reported number | A metric and a report manifest |
| Query large tables before collecting into R | `dl_read(..., lazy = TRUE)` |
| Work with SQL models or related tables | Optional dbt or dm modules |
| Use DuckLake, S3 or a remote catalog | Explicit storage configuration |

The [walkthrough](https://janwein.github.io/lakefold/articles/getting-started.html)
introduces these choices when the example needs them. It explains each call,
shows expected results and includes a
[runnable R script](https://github.com/JanWein/lakefold/blob/main/inst/examples/monthly_reporting.R).
You do not need to learn the complete API first.

## Go further

| Question | Guide |
|---|---|
| How do I use the new everyday operations? | [Everyday workflows](https://janwein.github.io/lakefold/articles/everyday-workflows.html) |
| How do checks, corrections and retries behave? | [Quality and history](https://janwein.github.io/lakefold/articles/quality-history.html) |
| How do I add pointblank rules and reports? | [Quality gates](https://janwein.github.io/lakefold/articles/quality-gates.html) |
| How do I compose processing steps? | [Workflow design](https://janwein.github.io/lakefold/articles/workflow-design.html) |
| How do I define reusable calculations? | [Products and metrics](https://janwein.github.io/lakefold/articles/products-metrics.html) |
| How do dbt, DuckLake and dm fit together? | [dbt workflows](https://janwein.github.io/lakefold/articles/dbt-workflows.html) |
| How do I schedule and operate this? | [Operations](https://github.com/JanWein/lakefold/blob/main/docs/OPERATIONS.md) |
| What is implemented and tested? | [Features](https://github.com/JanWein/lakefold/blob/main/docs/FEATURES.md) and [validation record](https://github.com/JanWein/lakefold/blob/main/docs/VALIDATION.md) |
| Which arguments does a function accept? | [Function reference](https://janwein.github.io/lakefold/reference/index.html) |
| How do I upgrade an existing project? | [Migration](https://github.com/JanWein/lakefold/blob/main/docs/MIGRATION.md) |

In R, use `?dl_open`, `?dl_write` or `help(package = "lakefold")`.
The online guides need no local vignette installation. To install local guides,
use `remotes::install_github("JanWein/lakefold", build_vignettes = TRUE)` with
Pandoc available, then `vignette("why-lakefold", package = "lakefold")`.

Development version **0.6.0** requires one coordinated registry writer.
Scheduling, access permissions and backups belong to your operating environment.
Production S3/PostgreSQL and sustained large workloads still need verification
in the target environment; the validation record states the tested scope.

## Development

The [contribution guide](CONTRIBUTING.md) covers formatting, tests and full
package checks. Development follows the Posit
[`r-package-development` and `testing-r-packages` skills](https://github.com/posit-dev/skills)
and the [R Packages documentation guidelines](https://r-pkgs.org/man.html).
Function help comes from roxygen2 comments, executable vignettes are checked,
and GitHub Actions publishes the pkgdown website. Package documentation is in English.

The package was previously named **dataloom**. Existing `dl_*` function names
remain available. MIT licensed.
