# root slots explicitly replace results while other pinned inputs persist

    Code
      tw_replace_sources(root, orders = newer)
    Condition
      Error in `abort()`:
      ! Unknown replacement source: orders. Available names: current, historical.

# invalid and overlapping source selectors fail before execution

    Code
      tw_replace_sources(root, missing = leaf)
    Condition
      Error in `abort()`:
      ! Unknown replacement source: missing. Available names: branch, leaf.

---

    Code
      tw_replace_sources(root, leaf = leaf, leaf = leaf)
    Condition
      Error in `abort()`:
      ! Supply uniquely named, non-empty replacement sources.

---

    Code
      tw_replace_sources(root, leaf)
    Condition
      Error in `abort()`:
      ! Supply uniquely named, non-empty replacement sources.

---

    Code
      tw_replace_sources(root, branch = tw_product("branch", data.frame(id = 1L)),
      leaf = leaf)
    Condition
      Error in `abort()`:
      ! Overlapping replacements discard requested sources: leaf

---

    Code
      tw_replace_sources(ambiguous, leaf = leaf)
    Condition
      Error in `abort()`:
      ! Ambiguous root alias and product ID: leaf

---

    Code
      tw_replace_sources(root, branch = cyclic)
    Condition
      Error in `abort()`:
      ! Product dependency cycle: root -> branch -> root

---

    Code
      tw_replace_sources(conflict, branch = branch)
    Condition
      Error in `abort()`:
      ! Different product definitions share the ID: leaf

# managed dbt bindings change without reading a database or writing files

    Code
      tw_replace_sources(project, orders = corrected)
    Condition
      Error in `abort()`:
      ! Ambiguous dbt source binding; use group.table: orders

---

    Code
      tw_replace_sources(project, inputs.orders = corrected, historical.orders = NULL)
    Condition
      Error in `abort()`:
      ! Each source needs a successful immutable lake release, with its asset, release, run and configuration.

---

    Code
      tw_replace_sources(changed, unknown = corrected)
    Condition
      Error in `abort()`:
      ! Unknown dbt source binding: unknown. Available names: inputs.orders, inputs.customers, historical.orders.

# correcting a product input retains its transformations and quality gates

    Code
      tw_replace_sources(tw_product("root", multiple), multiple = data.frame(id = 2L))
    Condition
      Error in `abort()`:
      ! Replacing a product input requires exactly one primary source at `multiple`. Use sources = list(name = value) to select a deeper input or supply an edited product definition.

