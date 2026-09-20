# automatic contracts are inferred after transforms and preserve schemas and rules

    Code
      write_data(lake, data.frame(total = 50), "orders")
    Condition
      Error in `abort()`:
      ! This asset has explicit quality rules. Use its composed product to keep those checks active.

# readonly targets reject a workflow before calling its source

    Code
      run(product)
    Condition
      Error in `abort()`:
      ! This lake is read-only. Open a writable connection for this operation.

