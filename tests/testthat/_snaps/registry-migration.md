# legacy quality evidence survives an idempotent registry migration

    Code
      lakefold:::registry_init(f$lake)
    Condition
      Error in `abort()`:
      ! Registry schema is newer than this lakefold version supports.

