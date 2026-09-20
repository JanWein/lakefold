# formula-engine configuration errors explain the custom-agent escape hatch

    Code
      quality_rule("bad", function(data) TRUE, engine = "pointblank")
    Condition
      Error in `abort()`:
      ! Pointblank formula rules need a one-sided formula. Use pointblank_checks() for an agent builder.

