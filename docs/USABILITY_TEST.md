# Simulated first use

This is an executed R walkthrough with simulated novice choices, not an
independent human usability study. The assumed user knows data frames, pipes and
dplyr, but not tidyweave. Installation and rendered PDF authoring are outside
the task. All data are synthetic.

The reference is the structural approach in the
[tidymodels recipe/workflow tutorial](https://www.tidymodels.org/start/recipes/):
define reusable instructions, execute them, inspect ordinary results, and apply
the same instructions to new data. This is a design criterion, not a measured
claim that two packages have equal usability.

## Acceptance task

Combine three complete deliveries (payments, contracts, brokers), diagnose a
negative payment, issue a report by company, accept a corrected payment and a
corrected reference delivery, then reopen the original report. Required business
decisions are the payment key, lookup relationships, allowed amounts, grouping,
snapshot meaning and explicit report approval.

Pass criteria:

* Input names remain identical during definition, inspection and replacement.
* Failed trial results can be inspected without exception handling or internal
  classes. A single failed row rule needs no repeated predicate.
* The calculation makes its grouping explicit; overall totals are not presented
  as grouped reports.
* Corrections reuse checks and preparation and do not mutate the definition or
  previous publications.
* Both reports reopen with the issued values after later corrections.
* The learned correction and diagnosis operations transfer to a broker change,
  missing contract and duplicate payment.

## Iterations

| Round | Observation | Change |
|---|---|---|
| Baseline | Reference corrections exposed `transform:lookup_1:lookup`; failed trials required exception handling; dimensions did not select grouping. | Established the three-delivery acceptance task. |
| 1 | Named lookup corrections and direct failed-trial results worked. Combining `data` with `sources` still required a detour. | Stable lookup names, public name display, default diagnostic trials, automatic single-rule row selection, explicit grouping feedback; allow distinct simultaneous replacements. |
| 2 | The full tutorial reached 350, then 380, while preserving both reports. A grouping reminder initially appeared even before invalid calculations; a shared product used twice collided with its inferred name. | Move reminders after successful calculations; share a single delivery name across references to the same product. Keep conflicting definitions rejected. |
| 3 | Transfer tasks exercise a broker correction, unmatched contract and duplicate payment. A collected report table no longer has issuance evidence. | Keep one correction grammar and add an actionable message directing the user to the original measurement result. |

The canonical tutorial is `vignettes/three-deliveries.Rmd`; its generated
download is `inst/examples/everyday_workflows.R`. Run the complete journey and
transfer cases against an installed package with
`Rscript scripts/simulate-first-use.R`. Assertions check the numbers, not just
whether commands returned successfully.

The installed-package run passed all acceptance and transfer assertions:
North/South were 300/50 in the first report and 300/80 in the correction. Moving
the corrected contract to North produced 380 there without altering either
issued report. Missing-contract diagnosis selected T3; duplicate-payment
diagnosis selected both T3 rows; the broker correction changed only its channel.

## Remaining boundaries

The user still needs to understand a reusable definition versus an execution,
trial versus publication, permitted dimensions versus report grouping, and
business approval versus report identity. The tutorial introduces each at the
point it is needed. Storage engines, connections, internal source paths and
release IDs are not required for this task.

General joins still use ordinary dplyr on tables; checked enrichment uses
`tw_add_lookup()`. The `left_join()` product method explains that boundary rather
than silently imposing different join semantics. Approval is never inferred.
Full-snapshot replacement is never guessed from partial rows.

Passing this simulation supports the specific everyday workflow. A separate
first-time human test is needed before claiming comparable learnability to
tidymodels across the whole package.
