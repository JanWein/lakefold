# delivery names survive simultaneous corrections without changing definitions

    Code
      dplyr::left_join(definition, policies, by = "policy")
    Condition
      Error in `abort()`:
      ! To enrich a product with a reference table, use tw_add_lookup(reference, by = ..., name = "reference"). It checks unique reference keys and matching input keys. For other join relationships, use dplyr::left_join() on ordinary tables inside tw_add_transform().

---

    Code
      tw_replace_sources(definition, unknown = policies)
    Condition
      Error in `abort()`:
      ! Unknown replacement source: unknown. Available names: brokers, payments, policies.

---

    Code
      tw_trial(definition, data = policies, sources = list(payments = policies))
    Condition
      Error in `abort()`:
      ! Delivery 'payments' was supplied in both data and sources. Supply it once, not both.

# lookup names can be explicit and cannot silently select another delivery

    Code
      tw_add_lookup(definition, data.frame(id = 1L), by = "id", name = "contracts")
    Condition
      Error in `abort()`:
      ! Delivery name 'contracts' is already used. Supply a unique name in tw_add_lookup(name = ).

---

    Code
      tw_replace_sources(ambiguous, contracts = data.frame(id = 1L))
    Condition
      Error in `abort()`:
      ! Ambiguous delivery name and product ID: contracts

# trial retains a failed result and row diagnostics select a single rule

    Code
      tw_collect(result)
    Condition
      Error in `abort()`:
      ! payments is blocked; no successful output is available. 1 check requiring attention: nonnegative: failed (1 of 3 checks failed). Inspect tw_quality_report(result) for checks and tw_quality_rows(result) for affected rows.

---

    Code
      tw_trial(definition, stop_on_failure = TRUE)
    Condition
      Error in `abort()`:
      ! payments is blocked; no successful output is available. 1 check requiring attention: nonnegative: failed (1 of 3 checks failed). For diagnosis, rerun with stop_on_failure = FALSE and save the result. Inspect tw_quality_report(result) and tw_quality_rows(result).

---

    Code
      tw_quality_rows(failed)
    Condition
      Error in `abort()`:
      ! Several checks need attention: nonnegative, ceiling. Select one with tw_quality_rows(result, rule = "nonnegative").

# overall and grouped measurements make the requested layout clear

    Code
      total <- tw_measure(result, metrics = definitions)
    Message
      Calculated an overall total. For grouped values use by = c("company"). Use by = character() for an explicit overall total.

---

    Code
      print(grouped)
    Output
      Grouped by: company
      # A tibble: 2 x 5
        company .metric .period .unit value
        <chr>   <chr>   <list>  <chr> <dbl>
      1 North   total   <NULL>  ""      100
      2 South   total   <NULL>  ""       50

---

    Code
      print(tw_measure(result, metrics = definitions, by = character()))
    Output
      Overall total (no grouping)
      # A tibble: 1 x 4
        .metric .period .unit value
        <chr>   <list>  <chr> <dbl>
      1 total   <NULL>  ""      150
