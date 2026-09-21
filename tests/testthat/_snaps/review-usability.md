# trial disables writers and catalogs throughout dependencies

    Code
      dr_report_release(measured, "trial", code_version = "v1")
    Condition
      Error in `FUN()`:
      ! Trial measurements cannot be saved in reports. Publish the product and recalculate first.
