# blocked results explain actual checks without counting rows twice

    Code
      tw_collect(result)
    Condition
      Error in `abort()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). Inspect tw_quality_report(result) for checks and tw_quality_rows(result) for affected rows.

# default failed runs explain checks and retain inspectable evidence

    Code
      tw_run(definition)
    Condition
      Error in `abort()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). For diagnosis, rerun with stop_on_failure = FALSE and save the result. Inspect tw_quality_report(result) and tw_quality_rows(result).

