# lookup key errors explain the equality-only boundary

    Code
      tw_add_lookup(tw_product("orders"), data.frame(id = 1L), by = dplyr::join_by(
        id > id))
    Condition
      Error in `abort()`:
      ! A checked lookup needs equality keys. Use an ordinary dplyr join for other relationships.

