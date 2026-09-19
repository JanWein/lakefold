# drafts infer types only and require an explicit review transition

    Code
      dl_validate(data, draft)
    Condition
      Error in `abort()`:
      ! Review the contract draft and call dl_contract_confirm() first.

---

    Code
      dl_contract_from(data.frame(x = factor("a")), "x", "Analytics", "Category",
      "One category")
    Condition
      Error in `abort()`:
      ! Convert unsupported classed columns explicitly before drafting.

