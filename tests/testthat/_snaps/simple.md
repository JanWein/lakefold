# explicit contracts can add rules but cannot be silently dropped

    Code
      dl_write(lake, data, "orders")
    Condition
      Error in `abort()`:
      ! This asset uses an explicit contract. Supply contract to keep its checks active.

# custom rule closures are re-evaluated unless explicitly versioned

    Code
      dl_write(lake, data, "orders", contract, cache = TRUE)
    Condition
      Error in `abort()`:
      ! Supply code_version to cache custom readers or rules, or leave cache unset.

# reopening refuses an accidental backend switch

    Code
      dl_open(root, backend = "ducklake")
    Condition
      Error in `abort()`:
      ! This folder uses a different backend. Reopen without backend or choose a new folder.

# existing unmarked catalogs are not adopted implicitly

    Code
      dl_open(root)
    Condition
      Error in `abort()`:
      ! This folder already contains lake files without lakefold.json. Use its original dl_config() or choose an empty folder.

# a data expression needs a deliberate asset name

    Code
      dl_write(lake, data.frame(id = 1L))
    Condition
      Error in `abort()`:
      ! Supply name when writing a data frame expression, for example name = 'orders'.

# contract drafts keep review explicit with optional metadata

    Code
      dl_write(lake, data.frame(id = 1L), "orders", contract = draft)
    Condition
      Error in `abort()`:
      ! Review the contract draft and call dl_contract_confirm() first.

