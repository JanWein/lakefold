# Documentation review

> Historical review of the previous five-lesson documentation. The current
> structure follows product specifications, preparation recipes and workflows.
> See [Get started](https://janwein.github.io/tidyweave/articles/get-started.html)
> and [Articles](https://janwein.github.io/tidyweave/articles/learn.html).

## Findings and changes

| Finding | Why it obstructed learning | Change |
|---|---|---|
| The homepage introduced the whole platform | Too many choices before a first result | One example and a prominent beginner route |
| Several competing starter articles | No reliable next step | Five ordered, self-contained lessons |
| Similar tasks used run, source replacement or direct lake calls interchangeably | Readers could not tell which path to adopt | trial for exploration; publish with data for deliveries; metric_set for the beginner report |
| The monthly case study was named getting-started but needed advanced concepts | Readers reached partition semantics too early | Keep the URL, label it lesson 5 and add a separate introductory hub |
| Architecture and implementation records looked like current instructions | Old design language competed with current behavior | Separate developer section and historical-record banners |
| Advanced articles lacked prerequisites and completion routes | Readers could not judge whether an integration was required | Purpose, dependencies and navigation on every guide |
| Report, release, target and layer were introduced before their need | Internal language obscured the task | Define terms at first use and provide a glossary |
| Pages was only built after merging | Broken navigation could reach the published site | Build and check site links on pull requests; deploy only main |

## Learning design

The structural reference is [tidymodels Get Started](https://www.tidymodels.org/start/)
and [Learn](https://www.tidymodels.org/learn/): a small ordered course first,
task-focused articles afterward. Text and examples are specific to tidyweave.
No claim of equal usability follows from adopting this structure.

The first four lessons use orders with total 150, then a correction to 155.
Lesson 5 adds complete-date replacement and a stock calculation: August 350,
corrected August 370, September 390, original issued report 350.

## Verification protocol

1. Generate package help and check reference coverage.
2. Render the entire pkgdown site with real DuckLake enabled.
3. Run each introductory lesson independently from its visible code; verify its
   asserted totals, blocked delivery and preserved report.
4. Extract canonical downloadable scripts and execute the changed runners.
5. Check local page links and fragment targets in generated HTML.
6. Check the learning route from home to each next lesson and back to Learn.

Optional external services are not certified by rendering configuration snippets.
The simulated walkthrough is not an independent human usability study.

## Executed verification, 21 September 2026

- The complete pkgdown site built with real DuckLake enabled: all 23 article
  sources and the function reference rendered. The two environment-dependent
  dbt reference examples were skipped because no external example project was
  configured. The advanced insurance CLI walkthrough retained its opt-in gate.
- The five beginner lessons and the repeated-workflow guide passed in separate
  R processes using only visible executable chunks, without hidden setup or
  objects from earlier lessons. Checks confirmed blocked bad data, totals
  150/155, monthly totals 350/370/390 and unchanged saved report values.
- The two changed extracted scripts, composition and monthly reporting, ran.
- The generated site link check covered 164 HTML pages and 3,742 local links and
  fragments with zero errors. This includes alias redirect pages.
- The route home → introduction → lessons 1 through 5 → Learn was checked against
  generated HTML. The reference inventory and workflow YAML also passed checks.
- A visible SQL missing-value warning in the monthly example prompted a final
  refinement: explicit `na.rm = TRUE` in the affected SQL summary expressions.
  This does not weaken the metrics' default missing-input rejection policy.

This is an executed documentation walkthrough, not independent user research.
Remote service setup and browser screenshot review were not part of this check.

## Integrating the first-use changes from PR #15

The revised lessons reflect trial's diagnostic default, automatic failed-rule
selection and explicit grouping via `by`. The three-delivery walkthrough is
preserved as `three-deliveries.Rmd` alongside the separate orchestration guide.
Named lookup replacement is shown in the composition guide. The generated
`everyday_workflows.R` script and first-use simulator retain their filenames.
Earlier validation counts above describe the original documentation PR, before
this additional guide; the combined tree is verified separately during integration.
