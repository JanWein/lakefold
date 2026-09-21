# formula-engine configuration errors explain the custom-agent escape hatch

    Code
      tw_quality_rule("bad", function(data) TRUE, engine = "pointblank")
    Condition
      Error in `abort()`:
      ! Pointblank formula rules need a one-sided formula. Use tw_pointblank_checks() for an agent builder.

