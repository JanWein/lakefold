# Build a monthly reporting workflow, step by step

Start with [Why lakefold?](WHY_LAKEFOLD.md) if you are unsure what the package
adds to an ordinary import script. Then follow the
[complete executable walkthrough](https://janwein.github.io/lakefold/articles/getting-started.html).
It uses synthetic monthly reserve data and runs locally without credentials.

| Step | What you do | What you learn |
|---|---|---|
| 1 | Open a local lake | A dedicated folder is enough to start |
| 2 | Store August's delivery: North 100, South 250 | Write and read a dataset totaling 350 |
| 3 | Correct South to 270 | Current data totals 370; the first release still totals 350 |
| 4 | Require one row per entity/date | A duplicate is blocked and the successful data stays available |
| 5 | Add a complete September delivery | Month replacement keeps August 370 and September 390 together |
| 6, optional | Build monthly totals | Reuse a prepared table with recorded inputs |
| 7, optional | Define a reserve metric | Record the formula and select one reporting date |
| 8, optional | Record the original report | Preserve its value of 350 and the input version used |

Each step explains why it is needed, what each call does and the expected
result. Stop after Step 2 if you only need local storage, or after Step 4 if
checked complete replacement deliveries cover your use case. Products, metrics,
pointblank, dbt and remote infrastructure are optional.

The guide also explains real Excel/CSV readers, original-file preservation,
current versus historical data, retries, connection cleanup and recurring jobs.
Later steps reuse earlier objects in the same R session.

## Run the complete example

Install lakefold, then run the bundled script:

```r
install.packages("remotes")
remotes::install_github("JanWein/lakefold")
source(system.file("examples", "monthly_reporting.R", package = "lakefold"),
  echo = TRUE)
```

The script needs only lakefold and its normal dependencies. It uses a temporary
folder, verifies the central results and removes its own demo data afterwards.
Read or download [monthly_reporting.R](../inst/examples/monthly_reporting.R).
The canonical [vignette source](../vignettes/getting-started.Rmd) is checked as
part of `R CMD check`; its optional pointblank example runs when installed.
The Excel block is a template requiring your own workbook and readxl.

For persistent data, use a dedicated project path in your own script and close
it with `dl_close(lake)` when finished. Do not use the demo's temporary directory
for a production project.

Once the walkthrough makes sense, use the [API](API.md),
[workflow guide](WORKFLOWS.md) and [operations guide](OPERATIONS.md) for specific
next steps. The [validation record](VALIDATION.md) describes tested behavior.
