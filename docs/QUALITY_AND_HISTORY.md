# Quality, failures and historical data

For the new product-first interface, start with the [composition guide](https://janwein.github.io/lakefold/articles/composing-products.html).
Lake examples require optional DuckDB >= 1.5.5; existing workflows remain supported.


## Four time and version concepts

| Concept | Question answered |
|---|---|
| Business date (`business_date`) | Which date does the delivery describe? |
| Receipt (`received_at`) | When was the original archived? |
| Publication (`published_at`) | When was the validated data state released? |
| Definition version and `code_version` | Which business rules and code were used? |

`business_date` does not replace a date column in the data. Stock metrics select
their date through `time_column` and `at`. A new delivery for the same date is a
correction with its own release; it does not overwrite history.

## Quality states

| Status | Meaning | Publication allowed? |
|---|---|---|
| `passed` | Check completed within tolerance | Yes |
| `warning` | A non-blocking business rule was breached | Yes, with warning quality |
| `failed` | A blocking rule was breached | No |
| `error` | The check could not complete successfully | No |
| `not_checked` | No evaluable check, such as an inactive step | No |

Null checks are independent of individual rules. A rule's `na.rm = TRUE` does
not override the contract. Tolerances apply to test units, which need not be
rows. `dl_quality_counts(2, 100)` means two failures among 100 units;
`max_failure = 0.02` still permits this result.

`dl_pointblank(policy = "agent")` uses native action levels for each step and
segment. Warning allows publication; Stop/Error/Critical block it.
`policy = "rule"` retains the rule-level failure-ratio policy. Inactive steps,
evaluation errors and empty plans do not count as success under either policy.
There is no general force-publication switch.

## Diagnose failures

```r
out <- dl_execute(pipeline, lake, stop_on_failure = FALSE)
out$status
out$quality
out$error   # inspect technical errors locally

dl_status(out)
dl_quality(lake, run_id = out$run_id)
dl_quality_report(dl_quality(out), "quality.html")
```

Scheduled jobs should retain the default `stop_on_failure = TRUE`. Diagnostics
are persisted before an error is raised so that the scheduler can detect the
failed run. A caught condition exposes the run result as `condition$result`.
Raw exception text can contain private data and is not copied verbatim into the
registry or notification messages.

## History and cache

```r
old <- dl_tbl(lake, "finance.reserves", release = first_run$release_id)
current <- dl_tbl(lake, "finance.reserves")
```

Existing releases remain unchanged. The two entry points have different default
reuse policies because an interactive write and a scheduled retry express
different intentions:

| Entry point | Repeating the current delivery | Repeating an older delivery after a newer one |
|---|---|---|
| `dl_write()` | Reuses the current matching release | Publishes a new release to make the supplied data current |
| `dl_run(cache = TRUE)` | Reuses a matching successful release | Reuses the historical match and leaves the newer release current |

A reused result has status `cached`. The advanced runner also accepts
`cache = "current"` to restrict reuse to the current release, or `cache = FALSE`
to execute again. Reuse requires matching definitions, code and input identity;
custom callbacks on the simple path run again unless `code_version` is supplied.
See the [monthly walkthrough](https://janwein.github.io/lakefold/articles/getting-started.html)
for concrete current and pinned reads.

## Full or partition replacement

* `mode = "replace"`: the delivery contains the complete new data state.
* `mode = "replace_partition"`: each supplied partition fully replaces that
  partition; other partitions are retained.

Partition replacement is not a row-level upsert. An incomplete monthly delivery
would remove other rows for that month. Null partition keys and empty partition
deliveries are rejected. The implementation materializes the complete new state,
so it is not yet optimized for incremental storage.

## Notifications

A `notify = function(event) ...` callback connects existing email or ticket
transport. Without a callback, events remain `pending` and nothing is sent.
Transport errors produce `delivery_failed`. An incident already delivered is
suppressed; recurrence after recovery is reported again. Use `event_id` for
external idempotency. A process crash between external delivery and the registry
update can still cause duplicate notifications.
