# batch measurements separate stock dates and aggregate flows explicitly

    Code
      measure(f$lake, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `abort()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

# measurement sets retain pinned inputs and report evidence

    Code
      report_release(f$lake, "monthly", measure(original, metrics = list(renamed = metric)),
      "v1")
    Condition
      Error in `abort()`:
      ! Report id already exists with different content.

---

    Code
      report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

---

    Code
      collect(changed)
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

---

    Code
      report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `abort()`:
      ! Measurement set changed after calculation.

# managed report connections close on success and failure

    Code
      report_release(config, "one", measured, "v2")
    Condition
      Error in `abort()`:
      ! Report id already exists with different content.

---

    Code
      report_read(config, "missing")
    Condition
      Error in `abort()`:
      ! Report not found: missing

# batch measurement rejects ambiguous labels and grouping columns

    Code
      measure(NULL, metrics = list(x = metric, x = metric))
    Condition
      Error in `abort()`:
      ! Metric names must be nonmissing, nonempty and unique.

---

    Code
      measure(NULL, metric, metrics = list(metric))
    Condition
      Error in `abort()`:
      ! Supply either metric or metrics, not both.

---

    Code
      measure(NULL, metrics = list(metric), by = ".metric")
    Condition
      Error in `abort()`:
      ! Grouping columns cannot use .metric, .period, .unit or value.

---

    Code
      measure(NULL, metrics = list(metric), at = c(1, 1))
    Condition
      Error in `abort()`:
      ! at must contain unique, nonmissing dates and cannot be empty.

# batch calculation manages one owned connection and preserves closed result pins

    Code
      measure(original, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `abort()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

---

    Code
      collect(measured, unused = TRUE)
    Condition
      Error in `collect()`:
      ! `...` must be empty.
      x Problematic argument:
      * unused = TRUE

