# both folder entry points retain named roles and read-only opens do not write

    Code
      open_lake(root, layers = c("raw", "products"))
    Condition
      Error in `abort()`:
      ! This folder has different saved layers. Omit layers to reuse its configuration, or choose a new folder.

---

    Code
      setup_lake(path = root, landing = "elsewhere")
    Condition
      Error in `abort()`:
      ! Supply path or explicit catalog, storage and landing settings, not both.

---

    Code
      open_lake(root, backend = "ducklake")
    Condition
      Error in `abort()`:
      ! This folder uses a different backend. Reopen without backend or choose a new folder.

# older custom folders require explicit one-time recovery without adding schemas

    Code
      open_lake(root)
    Condition
      Error in `abort()`:
      ! This older folder did not save its layer configuration. Reopen once with layers = c("core", "marts", "raw", "staging") in your intended order. A writable open will remember this choice.

# old default folders upgrade and corrupt saved layers are rejected

    Code
      open_lake(root)
    Condition
      Error in `abort()`:
      ! Invalid tidyweave.json layers. Restore the folder's original configuration.

# saved configuration cannot be bypassed by an older definition

    Code
      connect_lake(stale)
    Condition
      Error in `abort()`:
      ! This folder has different saved layers. Omit layers to reuse its configuration, or choose a new folder.
