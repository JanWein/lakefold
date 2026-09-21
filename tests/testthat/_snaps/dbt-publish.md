# dbt releases preserve snapshots and revalidate mutable source relations

    Code
      tw_dbt_publish(f$lake, result, "model.shop.customer_revenue", contract,
      "shop.revenue", code_version = "v1")
    Condition
      Error in `abort()`:
      ! Publication requires a successful dbt build result.

