# blocked results explain actual checks without counting rows twice

    Code
      dr_collect(result)
    Condition
      Error in `dplyr::collect()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). Inspect dr_quality_report(result) for checks and dr_quality_rows(result) for affected rows.

# default failed runs explain checks and retain inspectable evidence

    Code
      dr_run(definition)
    Condition
      Error in `dr_run()`:
      ! orders is blocked; no successful output is available. 1 check requiring attention: amount: failed (1 of 3 checks failed). For diagnosis, rerun with stop_on_failure = FALSE and save the result. Inspect dr_quality_report(result) and dr_quality_rows(result).

