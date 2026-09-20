# One development API

Use `product()` with `add_source()`, `add_transform()`, optional checks and
`set_target()`. Execute with `run()` and extract a table with `collect()`.
`publish()` supplies a local lake target when one has not been chosen.

A derived table uses the same product constructor. Add another product or a
`source_release()` as its input. Named sources accumulate; changing an existing
source requires `replace = TRUE`. Internal step, ingest and build helpers are
not a second public workflow language.

This breaking development change deliberately provides no compatibility aliases.
See the [development release policy](MIGRATION.md),
[canonical tutorial](https://janwein.github.io/tidyweave/articles/composing-products.html)
and [function reference](https://janwein.github.io/tidyweave/reference/index.html).
