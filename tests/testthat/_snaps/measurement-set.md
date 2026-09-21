# batch measurements separate stock dates and aggregate flows explicitly

    Code
      dr_measure(f$lake, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `dr_measure()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

# measurement sets retain pinned inputs and report evidence

    Code
      dr_report_release(f$lake, "monthly", dr_measure(original, metrics = list(
        renamed = metric)), "v1")
    Message
      Calculated an overall total. For grouped values use by = c("company"). Use by = character() for an explicit overall total.
    Condition
      Error in `dr_report_release()`:
      ! Report id already exists with different content.

---

    Code
      dr_report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `dr_report_release()`:
      ! Measurement set changed after calculation.

---

    Code
      dr_collect(changed)
    Condition
      Error in `dplyr::collect()`:
      ! Measurement set changed after calculation.

---

    Code
      dr_report_release(f$lake, "bad", changed, "v1")
    Condition
      Error in `dr_report_release()`:
      ! Measurement set changed after calculation.

# managed report connections close on success and failure

    Code
      dr_report_release(config, "one", measured, "v2")
    Condition
      Error in `dr_report_release()`:
      ! Report id already exists with different content.

---

    Code
      dr_report_read(config, "missing")
    Condition
      Error in `dr_report_read()`:
      ! Report not found: missing

# batch measurement rejects ambiguous labels and grouping columns

    Code
      dr_measure(NULL, metrics = list(x = metric, x = metric))
    Condition
      Error in `dr_measure()`:
      ! Metric names must be nonmissing, nonempty and unique.

---

    Code
      dr_measure(NULL, metric, metrics = list(metric))
    Condition
      Error in `dr_measure()`:
      ! Supply either metric or metrics, not both.

---

    Code
      dr_measure(NULL, metrics = list(metric), by = ".metric")
    Condition
      Error in `dr_measure()`:
      ! Grouping columns cannot use .metric, .period, .unit or value.

---

    Code
      dr_measure(NULL, metrics = list(metric), at = c(1, 1))
    Condition
      Error in `dr_measure()`:
      ! at must contain unique, nonmissing dates and cannot be empty.

# batch calculation manages one owned connection and preserves closed result pins

    Code
      dr_measure(original, metrics = list(stock), at = dates, period = "aggregate")
    Condition
      Error in `dr_measure()`:
      ! Stock metrics require exactly one non-missing business date. Supply at.

---

    Code
      dr_collect(measured, unused = TRUE)
    Condition
      Error in `dplyr::collect()`:
      ! `...` must be empty.
      x Problematic argument:
      * unused = TRUE

