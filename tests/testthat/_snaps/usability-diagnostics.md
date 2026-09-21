# blocked results explain actual checks without counting rows twice

    Code
      collect(result)
    Condition
      Error in `abort()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). Inspect quality_report(result) for checks and quality_rows(result) for affected rows.

# default failed runs explain checks and retain inspectable evidence

    Code
      run(definition)
    Condition
      Error in `abort()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). For diagnosis, rerun with stop_on_failure = FALSE and save the result. Inspect quality_report(result) and quality_rows(result).

