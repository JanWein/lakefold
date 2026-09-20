# unsafe inheritance and unchanged identity have actionable errors

    Code
      contract_update(old, columns = c(extra = "numeric"))
    Condition
      Error in `abort()`:
      ! Change id for a derived contract or version for a revised definition.

---

    Code
      contract_update(old, version = "2", grain = "One month")
    Condition
      Error in `abort()`:
      ! Supply key explicitly after changing grain or a key column; use character() for no key.

---

    Code
      contract_update(old, version = "2", grain = "One month", key = character())
    Condition
      Error in `abort()`:
      ! Review and supply rules explicitly after removing columns, changing types or changing grain.

---

    Code
      contract_update(old, version = "2", remove = "amount")
    Condition
      Error in `abort()`:
      ! Supply required explicitly after removing a required column.

---

    Code
      contract_update(old, version = "2", remove = "amount", required = "id")
    Condition
      Error in `abort()`:
      ! Review and supply rules explicitly after removing columns, changing types or changing grain.

---

    Code
      contract_update(old, version = "2", columns = c(id = "character"))
    Condition
      Error in `abort()`:
      ! Supply key explicitly after changing grain or a key column; use character() for no key.

---

    Code
      contract_update(old, version = "2", columns = c(amount = "integer"))
    Condition
      Error in `abort()`:
      ! Review and supply rules explicitly after removing columns, changing types or changing grain.

---

    Code
      contract_update(old, version = "2", remove = "missing")
    Condition
      Error in `abort()`:
      ! remove must name declared contract columns.

---

    Code
      contract_update(old, version = "2", typo = TRUE)
    Condition
      Error in `abort()`:
      ! ... must contain unique named contract arguments.

---

    Code
      contract_update(old, version = "2", remove = "amount", columns = c(amount = "numeric"))
    Condition
      Error in `abort()`:
      ! A column cannot be both added and removed.

