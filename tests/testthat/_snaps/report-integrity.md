# reports preserve doubles and detect small numeric changes

    Code
      dr_report_release(f$lake, "changed", list(total = changed), "v1")
    Condition
      Error in `FUN()`:
      ! Metric result changed after calculation.

# nested report values are rejected before any report is written

    Code
      dr_report_release(f$lake, "nested", list(total = value), "v1")
    Condition
      Error in `FUN()`:
      ! Report columns must be atomic vectors. Expand nested metric values into named columns before recalculating and saving a report.
