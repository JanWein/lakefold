# unsupported local formats are rejected without rewriting configuration

    Code
      tw_lake_config(path = root)
    Condition
      Error in `abort()`:
      ! Unsupported local configuration format. Create a new lake with this package version.

# corrupt current layer settings are rejected without rewriting them

    Code
      tw_lake_config(path = root)
    Condition
      Error in `abort()`:
      ! Invalid tidyweave.json layers. Restore the folder's original configuration.

