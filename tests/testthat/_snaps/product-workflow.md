# invalid or conflicting slots explain how to repair them

    Code
      tw_add_product(tw_workflow(), 1)
    Condition
      Error in `abort()`:
      ! Supply a tw_product() specification.

# adding an occupied product slot requires update

    Code
      tw_add_product(tw_add_product(tw_workflow(), tw_product("a")), tw_product("b"))
    Condition
      Error in `abort()`:
      ! This workflow already has a product. Use tw_update_product().

# adding an occupied recipe slot requires update

    Code
      tw_add_recipe(tw_add_recipe(tw_workflow(), tw_recipe()), tw_recipe())
    Condition
      Error in `abort()`:
      ! This workflow already has a recipe. Use tw_update_recipe().

# preparation stays in a dedicated workflow slot

    Code
      tw_add_product(tw_workflow(), dplyr::mutate(tw_product("a"), amount = 1))
    Condition
      Error in `abort()`:
      ! Keep preparation in a recipe when using tw_add_product().

# sources cannot silently shadow product inputs

    Code
      tw_add_product(tw_add_source(tw_workflow(), data.frame(id = 1L)), tw_product(
        "a", data.frame(id = 2L)))
    Condition
      Error in `abort()`:
      ! Sources are already set on the product. Supply sources in one place.

# incomplete workflows explain the missing product

    Code
      tw_trial(tw_workflow(), data = data.frame(id = 1L))
    Condition
      Error in `abort()`:
      ! This workflow has no product. Use tw_add_product().

