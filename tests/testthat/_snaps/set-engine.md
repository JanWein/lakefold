# engine selection rejects unsupported options

    Code
      tw_set_engine(tw_quality_rule("positive", ~ amount > 0), "spark")
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "native", "pointblank"

# function checks cannot silently become pointblank builders

    Code
      tw_set_engine(tw_quality_rule("positive", function(data) all(data$amount > 0)),
      "pointblank")
    Condition
      Error in `abort()`:
      ! Pointblank formula rules need a one-sided formula. Use tw_pointblank_checks() for an agent builder.

