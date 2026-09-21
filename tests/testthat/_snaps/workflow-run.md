# invalid dependency graphs fail before any step runs

    Code
      dr_workflow(a = function(b) b, b = function(a) a, code_version = "v1")
    Condition
      Error in `abort()`:
      ! Workflow dependencies contain a cycle.

---

    Code
      dr_workflow(a = function(unknown) unknown, code_version = "v1")
    Condition
      Error in `abort()`:
      ! Every step argument must name a workflow input or step.
