# batch measurements separate stock dates and aggregate flows explicitly

    Code
      tw_measure(f$lake, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `abort()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

# measurement sets retain pinned inputs and report evidence

    Code
      tw_report_release(f$lake, "monthly", tw_measure(original, metrics = list(
        renamed = metric)), "v1")
    Message
      Calculated an overall total. For grouped values use by = c("company"). Use by = character() for an explicit overall total.
    Condition
      Error in `abort()`:
      ! Report id already exists with different content.

---

    Code
      tw_report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

---

    Code
      tw_collect(changed)
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

---

    Code
      tw_report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

# managed report connections close on success and failure

    Code
      tw_report_release(config, "one", measured, "v2")
    Condition
      Error in `abort()`:
      ! Report id already exists with different content.

---

    Code
      tw_report_read(config, "missing")
    Condition
      Error in `abort()`:
      ! Report not found: missing

# batch measurement rejects ambiguous labels and grouping columns

    Code
      tw_measure(NULL, metrics = list(x = metric, x = metric))
    Condition
      Error in `abort()`:
      ! Metric names must be nonmissing, nonempty and unique.

---

    Code
      tw_measure(NULL, metric, metrics = list(metric))
    Condition
      Error in `abort()`:
      ! Supply either metric or metrics, not both.

---

    Code
      tw_measure(NULL, metrics = list(metric), by = ".metric")
    Condition
      Error in `abort()`:
      ! Grouping columns cannot use .metric, .period, .unit or value.

---

    Code
      tw_measure(NULL, metrics = list(metric), at = c(1, 1))
    Condition
      Error in `abort()`:
      ! at must contain unique, nonmissing dates and cannot be empty.

# batch calculation manages one owned connection and preserves closed result pins

    Code
      tw_measure(original, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `abort()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

---

    Code
      tw_collect(measured, unused = TRUE)
    Condition
      Error in `dplyr::collect()`:
      ! `...` must be empty.
      x Problematic argument:
      * unused = TRUE

