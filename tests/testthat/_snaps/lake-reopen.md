# both folder entry points retain named roles and read-only opens do not write

    Code
      tw_open_lake(root, layers = c("raw", "products"))
    Condition
      Error in `abort()`:
      ! This folder has different saved layers. Omit layers to reuse its configuration, or choose a new folder.

---

    Code
      tw_setup_lake(path = root, landing = "elsewhere")
    Condition
      Error in `abort()`:
      ! Supply path or explicit catalog, storage and landing settings, not both.

---

    Code
      tw_open_lake(root, backend = "ducklake")
    Condition
      Error in `abort()`:
      ! This folder uses a different backend. Reopen without backend or choose a new folder.

# saved configuration cannot be bypassed by an older definition

    Code
      tw_connect_lake(stale)
    Condition
      Error in `abort()`:
      ! This folder has different saved layers. Omit layers to reuse its configuration, or choose a new folder.
