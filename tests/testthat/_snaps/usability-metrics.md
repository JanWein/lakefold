# related definitions share metadata without evaluating expressions

    Code
      tw_metric("m", "orders", expr = sum(amount), approved = TRUE)
    Condition
      Error in `abort()`:
      ! code_version must be a non-empty string.

---

    Code
      tw_metric_set("orders", total = sum(amount), time_behavior = c(other = "stock"))
    Condition
      Error in `abort()`:
      ! time_behavior must be a single value or uniquely named by metric.

# exploration computes without registration and cannot become a report

    Code
      tw_measure(f$lake, definitions$reserve, record = TRUE)
    Condition
      Error in `abort()`:
      ! Exploratory metrics cannot be recorded. Use record = FALSE.

---

    Code
      tw_report_release(values, "exploration", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Exploratory metrics cannot be saved in reports. After business review, define the metrics with approved = TRUE and code_version = "your-version", then tw_measure() again. Approval is your explicit declaration, not an automatic check.

---

    Code
      tw_report_release(single, "mutated", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Metric definition changed after calculation. Recalculate before reporting.

# data-first reports retain exact releases and borrow existing lakes

    Code
      tw_report_release(single, "bad-ref", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Report destination cannot be inferred. Supply to explicitly.

# mixed metric tables never round large integer counts

    Code
      measurement_set_table(values, metadata)
    Condition
      Error in `abort()`:
      ! These metrics mix decimal values with integers outside the exact numeric range. Collect the individual metric results separately to preserve their precision.

# report storage refuses integers it cannot read back exactly before IO

    Code
      tw_report_release(value, "huge-count", to = "unused", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Report storage cannot preserve these integers exactly. Integer64 report columns must be within -2^53 to 2^53. Keep larger values in a storage format with integer64 support.

