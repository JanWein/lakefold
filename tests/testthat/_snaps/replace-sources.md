# root slots explicitly replace results while other pinned inputs persist

    Code
      replace_sources(root, orders = newer)
    Condition
      Error in `abort()`:
      ! Unknown replacement source: orders

# invalid and overlapping source selectors fail before execution

    Code
      replace_sources(root, missing = leaf)
    Condition
      Error in `abort()`:
      ! Unknown replacement source: missing

---

    Code
      replace_sources(root, leaf = leaf, leaf = leaf)
    Condition
      Error in `abort()`:
      ! Supply uniquely named, non-empty replacement sources.

---

    Code
      replace_sources(root, leaf)
    Condition
      Error in `abort()`:
      ! Supply uniquely named, non-empty replacement sources.

---

    Code
      replace_sources(root, branch = product("branch", data.frame(id = 1L)), leaf = leaf)
    Condition
      Error in `abort()`:
      ! Overlapping replacements discard requested sources: leaf

---

    Code
      replace_sources(ambiguous, leaf = leaf)
    Condition
      Error in `abort()`:
      ! Ambiguous root alias and product ID: leaf

---

    Code
      replace_sources(root, branch = cyclic)
    Condition
      Error in `abort()`:
      ! Product dependency cycle: root -> branch -> root

---

    Code
      replace_sources(conflict, branch = branch)
    Condition
      Error in `abort()`:
      ! Different product definitions share the ID: leaf

# managed dbt bindings change without reading a database or writing files

    Code
      replace_sources(project, orders = corrected)
    Condition
      Error in `abort()`:
      ! Ambiguous dbt source binding; use group.table: orders

---

    Code
      replace_sources(project, inputs.orders = corrected, historical.orders = NULL)
    Condition
      Error in `abort()`:
      ! Each source needs a successful immutable lake release, with its asset, release, run and configuration.

---

    Code
      replace_sources(changed, unknown = corrected)
    Condition
      Error in `abort()`:
      ! Unknown dbt source binding: unknown

# correcting a product input retains its transformations and quality gates

    Code
      replace_sources(product("root", multiple), multiple = data.frame(id = 2L))
    Condition
      Error in `abort()`:
      ! Replacing a product input requires exactly one primary source; supply an edited product definition: multiple

