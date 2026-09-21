# invalid or conflicting slots explain how to repair them

    Code
      add_product(workflow(), 1)
    Condition
      Error in `abort()`:
      ! Supply a product() specification.

# adding an occupied product slot requires update

    Code
      add_product(add_product(workflow(), product("a")), product("b"))
    Condition
      Error in `abort()`:
      ! This workflow already has a product. Use update_product().

# adding an occupied recipe slot requires update

    Code
      add_recipe(add_recipe(workflow(), recipe()), recipe())
    Condition
      Error in `abort()`:
      ! This workflow already has a recipe. Use update_recipe().

# preparation stays in a dedicated workflow slot

    Code
      add_product(workflow(), dplyr::mutate(product("a"), amount = 1))
    Condition
      Error in `abort()`:
      ! Keep preparation in a recipe when using add_product().

# sources cannot silently shadow product inputs

    Code
      add_product(add_source(workflow(), data.frame(id = 1L)), product("a",
        data.frame(id = 2L)))
    Condition
      Error in `abort()`:
      ! Sources are already set on the product. Supply sources in one place.

# incomplete workflows explain the missing product

    Code
      trial(workflow(), data = data.frame(id = 1L))
    Condition
      Error in `abort()`:
      ! This workflow has no product. Use add_product().

