# Architecture and extension boundaries

The canonical, executable guide is
[Architecture and extension boundaries](https://janwein.github.io/tidyweave/articles/workflow-design.html).
Its source is [the package vignette](../vignettes/workflow-design.Rmd).

Design findings and remaining gaps are maintained in
[the critical review](REFACTOR_REVIEW.md) and
[the modern data stack comparison](MODERN_DATA_STACK.md).

The [unified grammar design](UNIFIED_GRAMMAR_PLAN.md) records the current 0.10.0
simplification. One product captures real dplyr operations, auxiliary lookup
dependencies and optional quality engines. Successful lake results normalize to
pinned releases; other results reuse submitted data or their original lazy query.
Managed dbt specifications derive connection and binding details
at execution, and ordinary SQL remains an explicit integration boundary.
