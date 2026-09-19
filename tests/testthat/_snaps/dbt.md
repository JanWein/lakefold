# inconsistent artifacts are rejected

    Code
      dl_dbt_status(root)
    Condition
      Error in `abort()`:
      ! dbt artifacts must belong to the same invocation.

# selectors cannot inject CLI flags

    Code
      dl_dbt_build(dl_dbt_project("."), select = "--profiles-dir")
    Condition
      Error in `abort()`:
      ! select must contain non-empty dbt selectors, not CLI flags.

# malformed optional fields cannot erase failed nodes

    Code
      dl_dbt_status(root)
    Condition
      Error in `abort()`:
      ! Invalid scalar dbt result field: failures

