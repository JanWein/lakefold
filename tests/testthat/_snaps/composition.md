# definition, inspection and validation never call user functions

    Code
      print(product)
    Output
      <Data product: orders >
      Source: R function 
      Transformations: 1 
      Contract: automatic structure 
      Quality: 0 rules
      Target: memory 
      Status: defined 
    Code
      dl_explain(product)
    Output
      Product: orders
      Read: R function
      Transform: 1 ordered step(s), using ordinary R tables.
      Check: inferred structure and 0 additional quality rule(s).
      Return: data and run evidence in memory. Use dl_publish() for durable storage.
      dl_validate() checks configuration; dl_run() executes the work. 

# invalid specifications fail before acquisition

    Code
      dl_validate(dl_product("orders"))
    Condition
      Error in `abort()`:
      ! This product has no source. Add one with dl_add_source().

# bad transformations preserve an actionable condition and run evidence

    Code
      dl_collect(result)
    Condition
      Error in `abort()`:
      ! This run has no successful output. Inspect dl_status() and dl_quality().

# contract prototypes, anonymous contracts and rule names normalize consistently

    Code
      dl_contract(columns = c(id = "integer", id = "numeric"))
    Condition
      Error in `abort()`:
      ! columns must be a named type vector.

# duplicate rule names across a contract and added checks fail preflight

    Code
      dl_validate(product)
    Condition
      Error in `abort()`:
      ! Contract and added quality rules must have unique names.

# catalog delivery gets metadata without data rows or connections

    Code
      result <- dl_run(product)
    Condition
      Warning:
      Catalog 1 metadata publication failed; data output remains available.
    Code
      print(result$status)
    Output
      [1] "completed"
    Code
      print(result$warnings)
    Output
      [1] "Catalog 1 metadata publication failed; data output remains available."

# execution warnings remain inspectable without entering metadata text

    Code
      result <- dl_run(product)
    Condition
      Warning:
      Execution produced 1 warning(s); inspect result$warning_conditions locally.
    Code
      print(result$warnings)
    Output
      [1] "Execution produced 1 warning(s); inspect result$warning_conditions locally."

