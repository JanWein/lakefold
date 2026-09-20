# trial disables writers and catalogs throughout dependencies

    Code
      report_release(measured, "trial", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Trial measurements cannot be saved in reports. Publish the product and recalculate first.
